//
//  MarkdownPMStyler.swift
//  MarkdownPM
//
//  The single owned styler. Both styler-composition sites (per-edit
//  `TextStylingService.restyle` and full-rebuild
//  `rebuildTextStorageAndStyle`) route their styling COMPOSE step through
//  `styledRanges`, which OWNS the styling pipeline: build the
//  `StylingContext`, emit the per-construct primary sequence, then run the
//  supplemental AST pass — primary-then-supplemental ordering and the
//  concatenation live in exactly one place. The apply loops stay at each
//  call site.
//
//  Phase 5 Stage B — the primary styler logic was relocated here verbatim
//  from the former `MarkdownStyler` enum + its `extension MarkdownStyler`
//  siblings (now `extension MarkdownPMStyler`). The caret-aware primary
//  pass runs first; `AppleASTSupplementalStyler.styleAttributes` (the
//  caret-unaware AST pass for BlockQuote / Strikethrough / Table /
//  ThematicBreak) runs LAST as an internal helper so its attributes win
//  per key (last-writer-wins).
//
//  `scopedRanges` drives the primary pass: nil drives the whole-document
//  full-rebuild path; a paragraph array drives the per-edit scoped path.
//  The supplemental pass is whole-document on both sites and takes no scope.
//
// Token-class–specific styling lives partly in this file (fenced/inline
// code, task list checkboxes, horizontal rules — historical) and partly
// in sibling extension files:
//   - MarkdownPMStyler+TextStyling.swift   (headings, emphasis)
//   - MarkdownPMStyler+Links.swift         (auto / markdown / wiki links)
//   - MarkdownPMStyler+Latex.swift         (block + inline LaTeX)
//   - MarkdownPMStyler+Images.swift        (image embeds)

import AppKit
import Foundation
import Markdown

// MARK: - Regexes used only by styling

extension MarkdownPMStyler {
    static let linkDataDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    static let incompleteLinkRegexes: [NSRegularExpression] = [
        "\\[\\]",
        "\\[\\[\\]\\]",
        "\\[[^\\]\\r\\n]*$",
        "\\[[^\\]\\r\\n]+\\](?!\\()",
        "\\[[^\\]\\r\\n]+\\]\\([^)\\r\\n]*$",
        "\\[[^\\]\\r\\n]+\\]\\(\\)",
    ].map { try! NSRegularExpression(pattern: $0) }
    static let taskListRegex: NSRegularExpression = try! NSRegularExpression(
        // `([ \t]*)` (zero-or-more) on the spacer group lets the no-space
        // `-[x]` / `-[ ]` shorthand render alongside GFM `- [x]` / `- [ ]`.
        // The bracket requires a non-empty inner char (`[ ]` / `[x]` / `[X]`):
        // the EMPTY `[]` is intentionally NOT a checkbox — it's the transient
        // shorthand that canonicalizes to GFM on the next space (see
        // MarkdownLists' shorthand→GFM transform), so it shows as literal text
        // until then.
        pattern: #"^([ \t]*)([-*+•]|\d+\.)([ \t]*)(\[[ xX]\])(?=[ \t])"#,
        options: [.anchorsMatchLines]
    )
}

// MARK: - Styling Context

extension MarkdownPMStyler {
    struct StylingContext {
        let text: String
        let nsText: NSString
        let fullRange: NSRange
        // When non-nil, scan-based sub-methods only scan these ranges.
        let scopedRanges: [NSRange]?
        let tokens: [MarkdownToken]
        let codeTokens: [MarkdownToken]
        let activeTokenIndices: Set<Int>
        let baseFont: NSFont
        let baseDescriptor: NSFontDescriptor
        let fontName: String
        let caretLocation: Int
        let layoutBridge: LayoutBridge?
        let baseDefaultLineHeight: CGFloat
        let baseParagraphSpacing: CGFloat
        let codeFont: NSFont
        let codeBackgroundColor: NSColor
        let codeParagraphStyle: NSParagraphStyle
        let hiddenMarkerFont: NSFont
        let inlineMarkerFont: NSFont
        let latexMarkerFont: NSFont
        let configuration: MarkdownPMConfiguration

        var services: MarkdownPMServices { configuration.services }

        /// Single accessor for the per-construct "is this token caret-active?"
        /// read. Wraps the resolved `activeTokenIndices` set — the set's
        /// construction (incl. the upstream math-overlap force-activation in
        /// `MarkdownDetection.computeActiveTokenIndices`) is unchanged; this
        /// only reads it. NOTE: the checkbox end-of-syntax reveal is a separate
        /// LOCAL `caretLocation`-based reimplementation and intentionally does
        /// NOT route through here.
        func isActive(tokenIndex index: Int) -> Bool {
            activeTokenIndices.contains(index)
        }
    }
}

typealias StyledRange = (range: NSRange, attributes: [NSAttributedString.Key: Any])

// MARK: - Public API

@MainActor
enum MarkdownPMStyler {

    /// Compose the primary + supplemental styled ranges for one styling
    /// pass. Owns the pipeline — primary per-construct sequence first, then
    /// the supplemental AST pass LAST so its attributes win per key
    /// (last-writer-wins). The caller owns applying the returned
    /// `[StyledRange]` to its text storage.
    static func styledRanges(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        baseFont: NSFont,
        layoutBridge: LayoutBridge?,
        caretLocation: Int,
        activeTokenIndices: Set<Int>,
        wikiLinkIDProvider: (NSRange) -> String? = { _ in nil },
        precomputedTokens: [MarkdownToken]?,
        scopedRanges: [NSRange]?,
        document: Document,
        lineIndex: LineOffsetIndex,
        configuration: MarkdownPMConfiguration
    ) -> [StyledRange] {
        var result = styleAttributes(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            layoutBridge: layoutBridge,
            caretLocation: caretLocation,
            activeTokenIndices: activeTokenIndices,
            wikiLinkIDProvider: wikiLinkIDProvider,
            precomputedTokens: precomputedTokens,
            scopedRanges: scopedRanges,
            configuration: configuration
        )

        // Supplemental pass: walk Apple swift-markdown's AST for GFM-and-
        // extended block types the regex tokenizer doesn't cover (BlockQuote,
        // Strikethrough, Table, ThematicBreak). Composes additively on top
        // of the primary constructs. Runs LAST so it wins per attribute key
        // (last-writer-wins). The styler emits NOTHING for ThematicBreak
        // (its `visitThematicBreak` is a no-op) — HR is sole-written by the
        // HRVisibility service.
        result += AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: document,
            lineIndex: lineIndex,
            baseFont: baseFont,
            theme: configuration.theme
        )

        return result
    }

    /// The caret-aware primary pass: build the `StylingContext`, then emit
    /// the per-construct sequence (lists → headings → emphasis → links →
    /// images → code → LaTeX → incomplete brackets → checkboxes → marker
    /// shrink). Relocated verbatim from the former `MarkdownStyler` enum.
    static func styleAttributes(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        layoutBridge: LayoutBridge? = nil,
        caretLocation: Int,
        activeTokenIndices: Set<Int>,
        wikiLinkIDProvider: (NSRange) -> String? = { _ in nil },
        precomputedTokens: [MarkdownToken]? = nil,
        scopedRanges: [NSRange]? = nil,
        configuration: MarkdownPMConfiguration = .default
    ) -> [StyledRange] {
        let tokens = precomputedTokens ?? MarkdownTokenizer.parseTokens(in: text)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let codeTokens = tokens.filter { $0.kind == .codeBlock || $0.kind == .inlineCode }
        let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let baseDefaultLineHeight = ceil(
            layoutBridge?.defaultLineHeight(for: baseFont)
                ?? (baseFont.ascender - baseFont.descender + baseFont.leading)
        )
        let baseParagraphSpacing = ceil(baseDefaultLineHeight * configuration.paragraph.spacingFactor)

        let codeFontSize = round(fontSize * configuration.codeBlock.fontSizeScale)
        let codeFont = configuration.services.syntaxHighlighter.codeFont(size: codeFontSize)
        let codeBackgroundColor = configuration.services.syntaxHighlighter.backgroundColor()
        let codeLineHeight: CGFloat =
            layoutBridge?.defaultLineHeight(for: codeFont)
            ?? (codeFont.ascender - codeFont.descender + codeFont.leading)
        let codeParagraphStyle: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byCharWrapping
            style.lineSpacing = 0
            let codeBlockSpacing = configuration.codeBlock.paragraphSpacing
            let codeBlockIndent = configuration.codeBlock.horizontalIndent
            style.paragraphSpacingBefore = codeBlockSpacing
            style.paragraphSpacing = codeBlockSpacing
            style.headIndent = codeBlockIndent
            style.firstLineHeadIndent = codeBlockIndent
            style.tailIndent = -codeBlockIndent
            style.minimumLineHeight = ceil(codeLineHeight)
            style.maximumLineHeight = ceil(codeLineHeight)
            return style
        }()

        let hiddenMarkerSize = configuration.markers.hiddenMarkerFontSize
        let ctx = StylingContext(
            text: text,
            nsText: nsText,
            fullRange: fullRange,
            scopedRanges: scopedRanges,
            tokens: tokens,
            codeTokens: codeTokens,
            activeTokenIndices: activeTokenIndices,
            baseFont: baseFont,
            baseDescriptor: baseFont.fontDescriptor,
            fontName: fontName,
            caretLocation: caretLocation,
            layoutBridge: layoutBridge,
            baseDefaultLineHeight: baseDefaultLineHeight,
            baseParagraphSpacing: baseParagraphSpacing,
            codeFont: codeFont,
            codeBackgroundColor: codeBackgroundColor,
            codeParagraphStyle: codeParagraphStyle,
            hiddenMarkerFont: codeFont,
            inlineMarkerFont: NSFont.systemFont(ofSize: hiddenMarkerSize),
            latexMarkerFont: NSFont(name: fontName, size: hiddenMarkerSize)
                ?? NSFont.systemFont(ofSize: hiddenMarkerSize),
            configuration: configuration
        )

        var result: [StyledRange] = []
        let listsEnabled = configuration.lists.helpersEnabled
        result += MarkdownLists.paragraphAttributes(
            for: text,
            baseFont: baseFont,
            nsText: nsText,
            fullRange: fullRange,
            listsEnabled: listsEnabled,
            defaultLineHeight: baseDefaultLineHeight,
            defaultParagraphSpacing: baseParagraphSpacing,
            configuration: configuration
        )
        result += styleHeadings(ctx)
        result += styleEmphasis(ctx)
        result += styleAutoLinks(ctx)
        result += styleWikiLinks(ctx, wikiLinkIDProvider: wikiLinkIDProvider)
        result += styleImageEmbeds(ctx)
        result += styleMarkdownLinks(ctx)
        result += styleCodeBlocks(ctx)
        result += styleInlineCode(ctx)
        result += styleBlockLatex(ctx)
        result += styleInlineLatex(ctx)
        // Horizontal rules are styled exclusively by the HRVisibility caret-
        // awareness service (the dynamic-syntax pattern's "service is sole
        // writer" rule). The styler emits NOTHING for ThematicBreak. See
        // `.claude/Guidelines/Markdown.md` §3.2 + L3.
        result += styleIncompleteLinkBrackets(ctx)
        result += styleTaskCheckboxes(ctx)
        result += shrinkInactiveMarkers(ctx)
        return result
    }
}

// MARK: - Shared helpers used by multiple styling extensions

extension MarkdownPMStyler {

    static func appendSecondaryMarkers(
        for token: MarkdownToken,
        to attrs: inout [StyledRange],
        theme: MarkdownPMTheme
    ) {
        token.markerRanges.forEach {
            attrs.append(($0, [.foregroundColor: theme.mutedText]))
        }
    }

    enum RenderedStandaloneBlockMode {
        case collapsedSource(markerTexts: [String])
        case visibleSource(imageGap: CGFloat)
    }

    static func appendRenderedStandaloneBlock(
        for token: MarkdownToken,
        rawContent: String,
        image: NSImage,
        imageBounds: CGRect,
        paragraphSpacingBefore: CGFloat,
        paragraphSpacing: CGFloat,
        alignment: NSTextAlignment,
        mode: RenderedStandaloneBlockMode,
        ctx: StylingContext,
        attrs: inout [StyledRange]
    ) -> Bool {
        guard let paraRange = token.standaloneParagraphRange(in: ctx.nsText) else { return false }

        let para = NSMutableParagraphStyle()
        let baseLineHeight = layoutBridgeDefaultLineHeight(for: ctx.baseFont, using: ctx.layoutBridge)
        para.paragraphSpacingBefore = max(para.paragraphSpacingBefore, paragraphSpacingBefore)
        para.alignment = alignment

        switch mode {
        case .collapsedSource(let markerTexts):
            let neededHeight = max(para.minimumLineHeight, imageBounds.height, baseLineHeight)
            para.minimumLineHeight = neededHeight
            para.maximumLineHeight = max(para.maximumLineHeight, neededHeight)
            para.paragraphSpacing = max(para.paragraphSpacing, paragraphSpacing)

            let collapsedPara = NSMutableParagraphStyle()
            collapsedPara.maximumLineHeight = 1
            collapsedPara.paragraphSpacing = 0
            collapsedPara.paragraphSpacingBefore = 0

            let leadingWhitespaceUnits = rawContent.utf16.prefix { codeUnit in
                guard let scalar = UnicodeScalar(UInt32(codeUnit)) else { return false }
                return CharacterSet.whitespacesAndNewlines.contains(scalar)
            }.count
            let contentEnd = NSMaxRange(token.contentRange)
            let anchorLocation = min(token.contentRange.location + leadingWhitespaceUnits, contentEnd - 1)

            var paragraphAttributes: [StyledRange] = []
            ctx.nsText.enumerateSubstrings(in: paraRange, options: .byParagraphs) { _, _, enclosingRange, _ in
                if NSLocationInRange(anchorLocation, enclosingRange) {
                    paragraphAttributes.append((enclosingRange, [.paragraphStyle: para]))
                } else {
                    paragraphAttributes.append((enclosingRange, [.paragraphStyle: collapsedPara]))
                }
            }
            attrs.append(contentsOf: paragraphAttributes)

            if leadingWhitespaceUnits > 0 {
                let leadingRange = NSRange(location: token.contentRange.location, length: leadingWhitespaceUnits)
                let leadingText = ctx.nsText.substring(with: leadingRange)
                attrs.append(
                    (
                        leadingRange,
                        [
                            .foregroundColor: NSColor.clear,
                            .font: ctx.latexMarkerFont,
                            .kern: -HeadingHelpers.textWidth(leadingText, font: ctx.latexMarkerFont),
                        ]
                    ))
            }

            let anchorRange = NSRange(location: anchorLocation, length: 1)
            let anchorChar = ctx.nsText.substring(with: anchorRange)
            attrs.append(
                (
                    anchorRange,
                    [
                        .latexImage: image,
                        .latexBounds: NSValue(rect: imageBounds),
                        .latexIsBlock: true,
                        .foregroundColor: NSColor.clear,
                        .font: ctx.latexMarkerFont,
                        .kern: imageBounds.width - HeadingHelpers.textWidth(anchorChar, font: ctx.latexMarkerFont),
                    ]
                ))

            let trailingStart = anchorLocation + 1
            let trailingLength = contentEnd - trailingStart
            if trailingLength > 0 {
                let trailingRange = NSRange(location: trailingStart, length: trailingLength)
                let trailingText = ctx.nsText.substring(with: trailingRange)
                attrs.append(
                    (
                        trailingRange,
                        [
                            .foregroundColor: NSColor.clear,
                            .font: ctx.latexMarkerFont,
                            .kern: -HeadingHelpers.textWidth(trailingText, font: ctx.latexMarkerFont),
                        ]
                    ))
            }

            for (index, markerRange) in token.markerRanges.enumerated() {
                let markerText =
                    markerTexts.indices.contains(index)
                    ? markerTexts[index]
                    : ctx.nsText.substring(with: markerRange)
                attrs.append(
                    (
                        markerRange,
                        [
                            .foregroundColor: NSColor.clear,
                            .font: ctx.latexMarkerFont,
                            .kern: -HeadingHelpers.textWidth(markerText, font: ctx.latexMarkerFont),
                        ]
                    ))
            }

            // Hide whitespace between paragraph start and token start
            // (e.g. a space before "![[") so it doesn't affect line layout.
            let preTokenLength = token.range.location - paraRange.location
            if preTokenLength > 0 {
                let preTokenRange = NSRange(location: paraRange.location, length: preTokenLength)
                let preTokenText = ctx.nsText.substring(with: preTokenRange)
                attrs.append(
                    (
                        preTokenRange,
                        [
                            .foregroundColor: NSColor.clear,
                            .font: ctx.latexMarkerFont,
                            .kern: -HeadingHelpers.textWidth(preTokenText, font: ctx.latexMarkerFont),
                        ]
                    ))
            }

        case .visibleSource(let imageGap):
            para.minimumLineHeight = max(para.minimumLineHeight, baseLineHeight)
            para.maximumLineHeight = max(para.maximumLineHeight, baseLineHeight)
            para.paragraphSpacing = max(para.paragraphSpacing, imageBounds.height + imageGap + paragraphSpacing)

            attrs.append((paraRange, [.paragraphStyle: para]))
            attrs.append(
                (
                    token.range,
                    [
                        .latexImage: image,
                        .latexBounds: NSValue(rect: imageBounds),
                        .latexIsBlock: true,
                        .latexBlockOffsetY: baseLineHeight + imageGap,
                    ]
                ))
            appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
        }

        return true
    }
}

// MARK: - Whole-document & inline-only styling kept inline (small helpers)

extension MarkdownPMStyler {

    // MARK: Incomplete Link Brackets

    static func styleIncompleteLinkBrackets(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        // `[[Name]]` is already styled by its dedicated link pass — the greedy
        // `\[...\]` regex would otherwise match the inner `[[Name]` of a
        // completed wikilink and stamp the systemBlue incompleteLink color
        // over the title (last-writer-wins overwriting the muted/link color).
        // Skip any match intersecting those token ranges — same intersection
        // guard `shrinkInactiveMarkers` uses for literal-target tokens.
        let resolvedLinkTokens = ctx.tokens.filter { $0.kind == .wikiLink }
        for regex in MarkdownPMStyler.incompleteLinkRegexes {
            for match in regex.matches(in: ctx.text, options: [], range: ctx.fullRange) {
                let matchRange = match.range
                if MarkdownDetection.isInsideCodeBlock(range: matchRange, codeTokens: ctx.codeTokens) { continue }
                if resolvedLinkTokens.contains(where: { NSIntersectionRange($0.range, matchRange).length > 0 }) {
                    continue
                }
                let substring = ctx.nsText.substring(with: matchRange)
                for (i, char) in substring.enumerated() {
                    let location = matchRange.location + i
                    if char == "[" || char == "]" || char == "(" || char == ")" {
                        let markerRange = NSRange(location: location, length: 1)
                        attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
                    } else {
                        let contentRange = NSRange(location: location, length: 1)
                        attrs.append(
                            (
                                contentRange,
                                [
                                    .foregroundColor: ctx.configuration.theme.incompleteLink.withAlphaComponent(
                                        ctx.configuration.link.incompleteLinkAlpha)
                                ]
                            ))
                    }
                }
            }
        }
        return attrs
    }

    // MARK: Shrink / Hide Inactive Markers

    static func shrinkInactiveMarkers(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        // Wikilink / image-embed target text is LITERAL — emphasis markers
        // (`*` / `_`) that land inside `[[target]]` / `![[embed]]` must stay
        // full-size so the target reads verbatim. Mirrors the D-EMPH-6
        // suppression guard in `styleEmphasis`: skip any emphasis-kind token
        // whose range intersects a wikiLink/imageEmbed range.
        let literalTargetTokens = ctx.tokens.filter {
            $0.kind == .wikiLink || $0.kind == .imageEmbed
        }
        for (i, token) in ctx.tokens.enumerated() where !ctx.isActive(tokenIndex: i) {
            if token.kind == .codeBlock || token.kind == .inlineCode || token.kind == .inlineLatex
                || token.kind == .imageEmbed
            {
                continue
            }
            switch token.kind {
            case .italic, .bold, .boldItalic:
                if literalTargetTokens.contains(where: {
                    NSIntersectionRange($0.range, token.range).length > 0
                }) { continue }
            default:
                break
            }
            // Block-code guard only. `ctx.codeTokens` mixes fenced code blocks
            // (`.codeBlock`) with inline spans (`.inlineCode`); intersecting an
            // inline span must NOT suppress marker-hiding. Otherwise a heading
            // (or other construct) whose line merely CONTAINS `` `code` `` keeps
            // its `#` markers visible after the caret leaves the line.
            let blockCodeTokens = ctx.codeTokens.filter { $0.kind == .codeBlock }
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: blockCodeTokens) {
                continue
            }
            let smallSize = ctx.configuration.markers.hiddenMarkerFontSize
            let smallFont = NSFont(name: ctx.fontName, size: smallSize) ?? NSFont.systemFont(ofSize: smallSize)
            if token.kind == .link && token.markerRanges.count >= 4 {
                let openParen = token.markerRanges[2]
                let closeParen = token.markerRanges[3]
                let hideRange = NSRange(
                    location: openParen.location,
                    length: (closeParen.location + closeParen.length) - openParen.location
                )
                attrs.append(
                    (
                        hideRange,
                        [
                            .font: smallFont,
                            .foregroundColor: NSColor.clear,
                        ]
                    ))
            }
            for m in token.markerRanges {
                attrs.append(
                    (
                        m,
                        [
                            .font: smallFont,
                            .kern: -smallFont.pointSize,
                        ]
                    ))
            }
        }
        return attrs
    }
}

// MARK: - Fenced code blocks + inline code

extension MarkdownPMStyler {

    // MARK: Fenced Code Blocks

    static func styleCodeBlocks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .codeBlock {
            let codeContent = ctx.nsText.substring(with: token.contentRange)
            let isActive = ctx.isActive(tokenIndex: idx)
            let language = MarkdownTokenizer.extractLanguage(from: token, in: ctx.text)
            attrs.append(
                (
                    token.range,
                    [
                        .font: ctx.codeFont,
                        .foregroundColor: ctx.configuration.theme.codeText,
                        // No per-char .backgroundColor here: the renderer's full-width
                        // box is the sole fill. Setting it re-filled over the box
                        // (double alpha → lighter at the text). Inline code keeps its.
                        .paragraphStyle: ctx.codeParagraphStyle,
                    ]
                ))

            if !codeContent.isEmpty,
                let highlighted = ctx.services.syntaxHighlighter.highlight(code: codeContent, language: language)
            {
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) {
                    highlightAttrs, range, _ in
                    guard let foregroundColor = highlightAttrs[.foregroundColor] else { return }
                    let absoluteRange = NSRange(
                        location: token.contentRange.location + range.location, length: range.length)
                    attrs.append((absoluteRange, [.foregroundColor: foregroundColor]))
                }
            }
            let markerAttributes: [NSAttributedString.Key: Any] =
                isActive
                ? [.foregroundColor: ctx.configuration.theme.mutedText, .font: ctx.codeFont]
                : [.foregroundColor: NSColor.clear, .font: ctx.hiddenMarkerFont]
            token.markerRanges.forEach { attrs.append(($0, markerAttributes)) }
        }
        return attrs
    }

    // MARK: Inline Code

    static func styleInlineCode(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .inlineCode {
            let isActive = ctx.isActive(tokenIndex: idx)
            attrs.append(
                (
                    token.contentRange,
                    [
                        .font: ctx.codeFont,
                        .foregroundColor: ctx.configuration.theme.codeText,
                        .backgroundColor: ctx.codeBackgroundColor,
                    ]
                ))
            let inlineMarkerAttributes: [NSAttributedString.Key: Any] =
                isActive
                ? [
                    .foregroundColor: ctx.configuration.theme.mutedText,
                    .font: ctx.codeFont,
                ]
                : [
                    .foregroundColor: ctx.configuration.theme.mutedText.withAlphaComponent(
                        ctx.configuration.markers.inlineCodeMarkerAlpha),
                    .font: ctx.inlineMarkerFont,
                ]
            token.markerRanges.forEach { attrs.append(($0, inlineMarkerAttributes)) }
        }
        return attrs
    }
}

// MARK: - GitHub-style task list checkboxes (`- [ ] / - [x]`)

extension MarkdownPMStyler {

    static func styleTaskCheckboxes(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let taskMatches = MarkdownPMStyler.taskListRegex.matches(in: ctx.text, options: [], range: ctx.fullRange)
        for match in taskMatches {
            let markerRange = match.range(at: 2)
            let spacerRange = match.range(at: 3)
            let checkboxRange = match.range(at: 4)
            if checkboxRange.location == NSNotFound { continue }
            if MarkdownDetection.isInsideCodeBlock(range: checkboxRange, codeTokens: ctx.codeTokens) { continue }
            let checkboxText = ctx.nsText.substring(with: checkboxRange)
            let isChecked = checkboxText.range(of: "[x]", options: [.caseInsensitive]) != nil
            if markerRange.location != NSNotFound {
                let syntaxStart = markerRange.location
                let syntaxEnd = checkboxRange.location + checkboxRange.length
                let syntaxRange = NSRange(location: syntaxStart, length: max(0, syntaxEnd - syntaxStart))
                var isActiveSyntax = NSLocationInRange(ctx.caretLocation, syntaxRange)
                if !isActiveSyntax && ctx.caretLocation == syntaxEnd {
                    let lastIndex = syntaxEnd - 1
                    if lastIndex >= syntaxStart && lastIndex < ctx.nsText.length {
                        let lastChar = ctx.nsText.substring(with: NSRange(location: lastIndex, length: 1))
                        if lastChar != "\n" { isActiveSyntax = true }
                    }
                }
                if isChecked {
                    let lineRange = ctx.nsText.lineRange(for: checkboxRange)
                    var lineEnd = lineRange.location + lineRange.length
                    if lineEnd > lineRange.location {
                        let lastCharRange = NSRange(location: lineEnd - 1, length: 1)
                        if ctx.nsText.substring(with: lastCharRange) == "\n" {
                            lineEnd -= 1
                        }
                    }
                    var contentStart = checkboxRange.location + checkboxRange.length
                    while contentStart < lineEnd {
                        let charRange = NSRange(location: contentStart, length: 1)
                        let char = ctx.nsText.substring(with: charRange)
                        if char == " " || char == "\t" {
                            contentStart += 1
                            continue
                        }
                        break
                    }
                    if contentStart < lineEnd {
                        attrs.append(
                            (
                                NSRange(location: contentStart, length: lineEnd - contentStart),
                                [
                                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                    .strikethroughColor: ctx.configuration.theme.strikethroughColor,
                                    // Dim the completed-task text so the row reads
                                    // as "done". Checkbox glyph keeps its accent
                                    // tint — it draws via `drawTaskCheckboxes` and
                                    // doesn't read this foreground attribute.
                                    .foregroundColor: ctx.configuration.theme.mutedText,
                                ]
                            ))
                    }
                }
                if isActiveSyntax { continue }
                let afterCheckboxIndex = checkboxRange.location + checkboxRange.length
                if afterCheckboxIndex < ctx.nsText.length {
                    let spaceRange = NSRange(location: afterCheckboxIndex, length: 1)
                    let spaceChar = ctx.nsText.substring(with: spaceRange)
                    if spaceChar == " " && !isChecked {
                        let extraSpacing = HeadingHelpers.checkboxExtraSpacing(
                            font: ctx.baseFont,
                            configuration: ctx.configuration.checkbox
                        )
                        attrs.append((spaceRange, [.kern: extraSpacing]))
                    }
                }
            }
            if markerRange.location != NSNotFound {
                attrs.append((markerRange, [.foregroundColor: NSColor.clear]))
            }
            if spacerRange.location != NSNotFound {
                attrs.append((spacerRange, [.foregroundColor: NSColor.clear]))
            }
            attrs.append(
                (
                    checkboxRange,
                    [
                        .taskCheckbox: isChecked,
                        .foregroundColor: NSColor.clear,
                    ]
                ))
        }
        return attrs
    }
}
