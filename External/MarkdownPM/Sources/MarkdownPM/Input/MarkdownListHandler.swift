//
//  MarkdownListHandler.swift
//  MarkdownPM
//
//  Created by Luca Chen on 18.02.26.
//

// Makes list editing feel natural by continuing items, handling indentation,
// and applying spacing/alignment that keeps lists easy to read.
import AppKit
import Markdown

@MainActor
struct MarkdownLists {
    static func performEdit(_ textView: NSTextView, replace range: NSRange, with string: String) {
        let ns = textView.string as NSString
        let loc = min(range.location, ns.length)
        let maxLen = ns.length - loc
        let len = min(range.length, max(0, maxLen))
        let safeRange = NSRange(location: loc, length: len)

        if let coord = textView.delegate as? MarkdownPMEditor.Coordinator { coord.isProgrammaticEdit = true }
        defer {
            if let coord = textView.delegate as? MarkdownPMEditor.Coordinator { coord.isProgrammaticEdit = false }
        }

        guard textView.shouldChangeText(in: safeRange, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: safeRange, with: string)
        textView.didChangeText()
    }

    static let listRegex = try! NSRegularExpression(
        // `[-*+•]` covers all CommonMark bullets (`-`, `*`, `+`) plus the
        // legacy Pommora `•`. `\s*\[[ xX]?\]` (zero-or-more whitespace before
        // brackets, optional single-char content inside) lets the Pommora
        // `-[]` and `-[x]` shorthand match alongside the GFM `- [ ]` form.
        pattern: #"^\s*((?:(\d+)\.|[-*+•])(?:\s*\[[ xX]?\])?\s+)"#
    )
    static let dashNoSpaceRegex = try! NSRegularExpression(pattern: #"^\s*-(?!\s)"#)
    static let leadingWhitespaceRegex = try! NSRegularExpression(pattern: #"^\s*"#)
    /// Matches a blockquote line prefix: optional leading whitespace, `>`,
    /// then one space or tab. Captures the WHOLE prefix (leading WS + `> `)
    /// so it can be replicated on the new line for Shift+Enter continuation.
    static let blockquoteMarkerRegex = try! NSRegularExpression(pattern: #"^[ \t]*>[ \t]"#)
    /// Matches lines containing ONLY a bare list marker (`-`, `*`, `+`, or
    /// `\d+\.`) with optional whitespace — i.e. the user typed the marker but
    /// no content yet. Used by `detectListContext` to trigger Case 1: Enter
    /// on a bare marker completes the marker + opens a new list item below.
    static let bareMarkerRegex = try! NSRegularExpression(pattern: #"^\s*([-*+]|\d+\.)\s*$"#)
    /// Matches a line that is ONLY a Pommora checkbox shorthand marker with no
    /// space between the bullet and the bracket — `-[]`, `-[ ]`, `-[x]`, `-[X]`
    /// (caret implied at line end). Group 1 = leading whitespace, group 2 =
    /// bullet char, group 3 = inner char (empty / space / x / X). Drives the
    /// space-triggered GFM canonicalization in `handleInsertion`.
    static let shorthandCheckboxRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+])\[([ xX]?)\]$"#)

    static func indentLevel(from leadingWhitespace: String) -> Int {
        let tabCount = leadingWhitespace.filter { $0 == "\t" }.count
        let spaceCount = leadingWhitespace.filter { $0 == " " }.count
        return tabCount + (spaceCount / 2)
    }

    // MARK: - List Context Detection

    /// Captures everything the Enter handler needs to know about the list item
    /// at the caret. Returned by `detectListContext`. See that function for the
    /// detection algorithm.
    struct ListContext {
        enum MarkerKind {
            case unordered(char: Character)  // '-', '*', '+' (or '•' from legacy files)
            case ordered(number: Int)  // current number for n+1 calc
        }
        var kind: MarkerKind
        var leadingWhitespace: String  // e.g. "  ", "\t", ""
        var hasCheckbox: Bool  // true for `- [ ]` / `- [x]`
        var contentStartOffsetInLine: Int  // position of first content char relative to line start
        var lineRange: NSRange  // full line range in document text
        var contentIsEmpty: Bool  // marker present, no content
        var isBareStartTrigger: Bool  // line is literally "-" or "1." (no trailing space)
        var caretIsAtLineEnd: Bool  // caret at/after last non-newline char
    }

    /// Three-stage detection: code-block guard → regex prefilter → AST confirmation.
    /// Returns nil when caret is not in a list item (or is in a code block, or the
    /// line parses as an HR / non-list paragraph).
    ///
    /// AST disambiguation: `---` parses as `ThematicBreak`, not `UnorderedList` — so
    /// HR lines naturally return nil here without special-case code. (Pommora removed
    /// Setext H2 support; `---` is always HR regardless of context.)
    ///
    /// Bare-marker trigger: when the line is literally `-` or `1.` (no trailing space),
    /// the AST parses it as a `Paragraph` (CommonMark requires a space after the marker
    /// to form a list). We recognize this case via `bareMarkerRegex` and set
    /// `isBareStartTrigger = true` — the Enter handler's Case 1 then completes the
    /// marker and inserts a new bullet.
    static func detectListContext(
        in textView: NSTextView,
        caretLocation: Int,
        isInCodeBlock: Bool
    ) -> ListContext? {
        if isInCodeBlock { return nil }

        let nsText = textView.string as NSString
        let safeLocation = min(caretLocation, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let fullLine = nsText.substring(with: lineRange)
        let fullLineUTF16 = fullLine.utf16.count

        // Stage 1: regex prefilter.
        let bareMarkerMatch = bareMarkerRegex.firstMatch(
            in: fullLine, range: NSRange(location: 0, length: fullLineUTF16))
        let listMatch = listRegex.firstMatch(
            in: fullLine, range: NSRange(location: 0, length: fullLineUTF16))
        guard bareMarkerMatch != nil || listMatch != nil else { return nil }

        // Stage 2: AST confirmation. Pre-trim leading whitespace so indented lists
        // (e.g. `\t- item` for nesting) parse correctly — leading tabs/spaces in
        // isolation would otherwise look like a code block to CommonMark. Also map
        // legacy Pommora `•` bullets to `-` for parsing only, so files written by
        // the pre-v0.2.7.3 `-` → `\t• ` space-trigger rewrite still detect as lists.
        let trimmedLine =
            fullLine
            .trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^•"#, with: "-", options: .regularExpression)
            // Pommora task shorthand has NO space between the marker and the
            // bracket (`-[x]`, `1.[ ]`) because auto-pair is suppressed after
            // `-`. CommonMark needs that space to form a list, so the AST would
            // otherwise see a plain paragraph and reject the line. Insert the
            // space for parsing only (the real offsets/checkbox flag come from
            // `listMatch` on the untouched `fullLine`).
            .replacingOccurrences(
                of: #"^([-*+]|\d+\.)\["#, with: "$1 [", options: .regularExpression)
        let document = Markdown.Document(parsing: trimmedLine)
        let isAstList = document.children.contains {
            $0 is Markdown.UnorderedList || $0 is Markdown.OrderedList
        }

        let isBareStartTrigger: Bool
        if isAstList {
            isBareStartTrigger = false
        } else if bareMarkerMatch != nil {
            isBareStartTrigger = true
        } else {
            return nil  // listRegex matched but AST rejected (HR / paragraph / etc.)
        }

        // Extract leading whitespace — preserved as indent prefix for new items.
        let leadingWhitespace: String
        if let wsMatch = leadingWhitespaceRegex.firstMatch(
            in: fullLine, range: NSRange(location: 0, length: fullLineUTF16))
        {
            leadingWhitespace = (fullLine as NSString).substring(with: wsMatch.range)
        } else {
            leadingWhitespace = ""
        }

        // Extract marker kind, content-start offset, checkbox flag, content emptiness.
        let kind: ListContext.MarkerKind
        let contentStartOffset: Int
        let hasCheckbox: Bool
        let contentIsEmpty: Bool

        if isBareStartTrigger, let match = bareMarkerMatch {
            let markerCapture = (fullLine as NSString).substring(with: match.range(at: 1))
            if markerCapture.hasSuffix(".") {
                let numStr = String(markerCapture.dropLast())
                kind = .ordered(number: Int(numStr) ?? 1)
            } else {
                kind = .unordered(char: markerCapture.first ?? Character("-"))
            }
            contentStartOffset = match.range.location + match.range.length
            hasCheckbox = false
            contentIsEmpty = true
        } else if let match = listMatch {
            let digitRange = match.range(at: 2)
            if digitRange.location != NSNotFound,
                let num = Int((fullLine as NSString).substring(with: digitRange))
            {
                kind = .ordered(number: num)
            } else {
                // First non-whitespace char is the bullet (preserves '-', '*', '+', '•').
                let bulletChar = fullLine.first(where: { !$0.isWhitespace }) ?? Character("-")
                kind = .unordered(char: bulletChar)
            }
            contentStartOffset = match.range.location + match.range.length
            let markerOuter = (fullLine as NSString).substring(with: match.range(at: 1))
            // Require a non-empty inner char (`[ ]` / `[x]` / `[X]`). The empty
            // `[]` is NOT a checkbox: the shorthand canonicalizes to GFM `- [ ]`
            // on the space that starts the content (see handleInsertion's
            // shorthand→GFM transform), so a bare `-[]` is a transient,
            // non-checkbox marker and continues as a plain bullet on Enter.
            hasCheckbox = markerOuter.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil
            let contentLength = max(0, fullLineUTF16 - contentStartOffset)
            let contentPart =
                (fullLine as NSString)
                .substring(with: NSRange(location: contentStartOffset, length: contentLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            contentIsEmpty = contentPart.isEmpty
        } else {
            return nil  // unreachable: guarded above
        }

        // Caret position relative to line.
        let caretOffsetInLine = safeLocation - lineRange.location
        let lineEnd = lineRange.length
        let hasTrailingNewline =
            lineEnd > 0
            && (fullLine as NSString).character(at: lineEnd - 1) == 10  // '\n'
        let lineContentLen = hasTrailingNewline ? lineEnd - 1 : lineEnd
        let caretIsAtLineEnd = caretOffsetInLine >= lineContentLen

        return ListContext(
            kind: kind,
            leadingWhitespace: leadingWhitespace,
            hasCheckbox: hasCheckbox,
            contentStartOffsetInLine: contentStartOffset,
            lineRange: lineRange,
            contentIsEmpty: contentIsEmpty,
            isBareStartTrigger: isBareStartTrigger,
            caretIsAtLineEnd: caretIsAtLineEnd
        )
    }

    // MARK: - Paragraph Attributes for List Styling

    static func paragraphAttributes(
        for text: String,
        baseFont: NSFont,
        nsText: NSString,
        fullRange: NSRange,
        listsEnabled: Bool,
        defaultLineHeight: CGFloat,
        defaultParagraphSpacing: CGFloat,
        configuration: MarkdownPMConfiguration = .default
    ) -> [(range: NSRange, attributes: [NSAttributedString.Key: Any])] {
        var attributesList: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        guard listsEnabled else { return attributesList }

        let indentPerLevel = configuration.lists.indentPerLevel
        let extraLineHeight = configuration.lists.extraLineHeight
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: baseFont]).width

        func applyListMatches(_ matches: [NSTextCheckingResult]) {
            for match in matches {
                let ps = NSMutableParagraphStyle()
                ps.minimumLineHeight = defaultLineHeight + extraLineHeight
                ps.maximumLineHeight = defaultLineHeight + extraLineHeight
                ps.lineSpacing = 0
                ps.paragraphSpacing = defaultParagraphSpacing
                ps.paragraphSpacingBefore = 0
                let wsRange = match.range(at: 1)
                let markerRange = match.range(at: 2)
                let ws = nsText.substring(with: wsRange)
                let tabCount = ws.filter { $0 == "\t" }.count
                let spaceCount = ws.filter { $0 == " " }.count
                let depthIndent = CGFloat(tabCount) * indentPerLevel + CGFloat(spaceCount) * spaceWidth

                let markerString = nsText.substring(with: markerRange) as NSString
                let markerWidth = markerString.size(withAttributes: [.font: baseFont]).width
                let hasCheckbox = markerString.range(of: "[").location != NSNotFound
                let isChecked = markerString.range(of: "[x]", options: [.caseInsensitive]).location != NSNotFound
                let extraSpacing =
                    (hasCheckbox && !isChecked)
                    ? HeadingHelpers.checkboxExtraSpacing(font: baseFont, configuration: configuration.checkbox)
                    : 0

                // Plain `-` bullet (not a task checkbox): widen the gap between
                // the rendered `•` glyph and the text by `bulletTextGap`. Added
                // to `headIndent` here (wrapped lines) and kerned onto the hidden
                // `-` below (first line) so both stay aligned.
                let markerStartsWithDash =
                    markerRange.length > 0
                    && nsText.substring(with: NSRange(location: markerRange.location, length: 1)) == "-"
                let isPlainDashBullet = markerStartsWithDash && !hasCheckbox
                let bulletTextGap: CGFloat = isPlainDashBullet ? configuration.lists.bulletTextGap : 0

                ps.tabStops = []
                ps.defaultTabInterval = indentPerLevel
                // Default visual indent (one tab-stop from page margin) on top
                // of any source-level nesting captured in depthIndent. Restores
                // the visual breathing room the pre-v0.2.7.3 `\t• ` rewrite
                // provided automatically — without putting `\t` chars in the
                // canonical source.
                ps.firstLineHeadIndent = indentPerLevel + depthIndent
                ps.headIndent = indentPerLevel + depthIndent + markerWidth + extraSpacing + bulletTextGap

                attributesList.append((match.range(at: 0), [.paragraphStyle: ps]))

                // Pommora marker rewrite — `-` prefix handling for bullets + tasks.
                // Only fires when the source marker char is `-` (not `*`, `+`, `•`).
                if markerRange.length > 0,
                    nsText.substring(with: NSRange(location: markerRange.location, length: 1)) == "-"
                {
                    if hasCheckbox {
                        // Task line — collapse the leading `-` and any spacer
                        // BEFORE the `[` bracket via font 0.1, so the drawn
                        // checkbox glyph is the only visible marker prefix. The
                        // `[` brackets themselves stay at body font (the checkbox
                        // draw reads `font.pointSize` from the `[` to compute its
                        // size — collapsing the brackets makes the box render
                        // near-zero size and disappear). Supports both GFM
                        // `- [ ] task` and Pommora `-[]` / `-[x]` syntax.
                        let group2 = nsText.substring(with: markerRange) as NSString
                        let bracketLocalOffset = group2.range(of: "[").location
                        if bracketLocalOffset != NSNotFound, bracketLocalOffset > 0 {
                            let collapseRange = NSRange(
                                location: markerRange.location, length: bracketLocalOffset)
                            attributesList.append(
                                (
                                    collapseRange,
                                    [
                                        .font: NSFont.systemFont(ofSize: 0.1),
                                        .foregroundColor: NSColor.clear,
                                    ]
                                ))
                        }
                    } else {
                        // Plain bullet line — hide the `-` so MarkdownTextLayoutFragment
                        // can overlay a `•` glyph. NOT collapsed (no font change), so
                        // the dash's natural width is preserved invisibly to keep the
                        // gap between the bullet glyph and the content. `bulletTextGap`
                        // is kerned in after the dash to widen that gap (matched by the
                        // same addition to `headIndent` above so wrapped lines align).
                        attributesList.append(
                            (
                                NSRange(location: markerRange.location, length: 1),
                                [
                                    .foregroundColor: NSColor.clear,
                                    .kern: bulletTextGap,
                                ]
                            ))
                    }
                }
            }
        }

        // Ordered lists
        let orderedListPattern = #"^([ \t]*)(\d+\.(?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#
        if let orderedListRegex = try? NSRegularExpression(pattern: orderedListPattern, options: [.anchorsMatchLines]) {
            applyListMatches(orderedListRegex.matches(in: text, options: [], range: fullRange))
        }

        // Bullet lists. Accepts `-`, `*`, `+` (CommonMark) and `•` (legacy Pommora).
        // Space between marker and brackets is OPTIONAL, and inner-bracket content
        // is also OPTIONAL, so the Pommora `-[]` / `-[x]` shorthand matches
        // alongside the GFM `- [ ]` / `- [x]` form.
        let bulletListPattern = #"^([ \t]*)([-*+•](?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$"#
        if let bulletListRegex = try? NSRegularExpression(pattern: bulletListPattern, options: [.anchorsMatchLines]) {
            applyListMatches(bulletListRegex.matches(in: text, options: [], range: fullRange))
        }
        return attributesList
    }

    // MARK: - Input Handling

    static func handleInsertion(textView: NSTextView, affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return true }

        // Em-dash auto-format: `--<non-dash>` → `—<non-dash>`. Triggers on any
        // single non-dash character typed after `--`. Skipped when char N-3 is
        // also `-` (preserves `---` HR, YAML frontmatter delim, 4+ dash HRs)
        // and inside fenced/inline code. Runs BEFORE the fast-path filter so
        // letter/digit keystrokes after `--` aren't short-circuited.
        if replacementString.count == 1,
            let ch = replacementString.first, ch != "-",
            affectedCharRange.length == 0,
            affectedCharRange.location >= 2
        {
            let nsText = textView.string as NSString
            let insertLoc = affectedCharRange.location
            let prev1 = nsText.substring(with: NSRange(location: insertLoc - 1, length: 1))
            let prev2 = nsText.substring(with: NSRange(location: insertLoc - 2, length: 1))
            if prev1 == "-" && prev2 == "-" {
                let hrConflict: Bool =
                    insertLoc >= 3
                    && nsText.substring(with: NSRange(location: insertLoc - 3, length: 1)) == "-"
                if !hrConflict {
                    let inCode = textView.string.contains("`")
                        ? MarkdownDetection.isInsideCodeBlock(location: insertLoc, in: textView.string)
                        : false
                    if !inCode {
                        let replaceRange = NSRange(location: insertLoc - 2, length: 2)
                        MarkdownLists.performEdit(textView, replace: replaceRange, with: "—" + replacementString)
                        textView.setSelectedRange(NSRange(location: insertLoc, length: 0))
                        return false
                    }
                }
            }
        }

        // Fast path: skip the expensive isInsideCodeBlock scan for ordinary typing.
        // `-` is included so the `<-` arrow auto-transform can inspect previousChar.
        if replacementString.count == 1,
            let ch = replacementString.first,
            ch != ">" && ch != "-" && ch != "[" && ch != "(" && ch != "{"
                && ch != "\t" && ch != " " && ch != "\n"
        {
            return true
        }

        let activeConfig = (textView as? NativeTextView)?.configuration ?? .default
        let listsEnabled = activeConfig.lists.helpersEnabled
        let autoClosePairsEnabled = activeConfig.lists.autoClosePairsEnabled

        func insertAutoPair(open openChar: String, close closeChar: String) -> Bool {
            let insertionLocation = affectedCharRange.location
            MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "\(openChar)\(closeChar)")
            textView.setSelectedRange(NSRange(location: insertionLocation + openChar.count, length: 0))
            return false
        }

        let isInCodeBlock =
            textView.string.contains("`")
            ? MarkdownDetection.isInsideCodeBlock(location: affectedCharRange.location, in: textView.string)
            : false
        if replacementString == ">" && affectedCharRange.length == 0 && !isInCodeBlock {
            let insertionLocation = affectedCharRange.location
            guard insertionLocation > 0 else { return true }
            let nsText = textView.string as NSString
            let previousCharRange = NSRange(location: insertionLocation - 1, length: 1)
            let previousChar = nsText.substring(with: previousCharRange)

            // Case A: chained "<-" → "←", then ">" → extend to "↔".
            if previousChar == "←" {
                MarkdownLists.performEdit(textView, replace: previousCharRange, with: "↔")
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return false
            }

            // Case B: pasted "<-" still literal in buffer; ">" → "↔".
            if previousChar == "-", insertionLocation >= 2 {
                let twoBackRange = NSRange(location: insertionLocation - 2, length: 1)
                if nsText.substring(with: twoBackRange) == "<" {
                    let combinedRange = NSRange(location: insertionLocation - 2, length: 2)
                    MarkdownLists.performEdit(textView, replace: combinedRange, with: "↔")
                    // Buffer shrank by 1; cursor sits just after the new "↔".
                    textView.setSelectedRange(NSRange(location: insertionLocation - 1, length: 0))
                    return false
                }
            }

            // Case C (existing): "->" → "→".
            if previousChar == "-" {
                MarkdownLists.performEdit(textView, replace: previousCharRange, with: "→")
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return false
            }
        }

        // "<-" → "←". When the user types "-" right after "<", swap the "<"
        // for "←" and suppress the typed "-". Chains naturally with Case A
        // above to produce "↔" when ">" is typed next.
        if replacementString == "-" && affectedCharRange.length == 0 && !isInCodeBlock {
            let insertionLocation = affectedCharRange.location
            guard insertionLocation > 0 else { return true }
            let nsText = textView.string as NSString
            let previousCharRange = NSRange(location: insertionLocation - 1, length: 1)
            if nsText.substring(with: previousCharRange) == "<" {
                MarkdownLists.performEdit(textView, replace: previousCharRange, with: "←")
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return false
            }
        }

        // En-dash → em-dash promotion. Typing `-` immediately adjacent to an
        // existing `–` (en-dash) upgrades it to `—` (em-dash) and consumes the
        // typed `-`. Fires on either side of the en-dash so the user can
        // promote regardless of where the caret was parked.
        if replacementString == "-" && affectedCharRange.length == 0 && !isInCodeBlock {
            let insertionLocation = affectedCharRange.location
            let nsText = textView.string as NSString
            if insertionLocation > 0 {
                let prevRange = NSRange(location: insertionLocation - 1, length: 1)
                if nsText.substring(with: prevRange) == "–" {
                    MarkdownLists.performEdit(textView, replace: prevRange, with: "—")
                    textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                    return false
                }
            }
            if insertionLocation < nsText.length {
                let nextRange = NSRange(location: insertionLocation, length: 1)
                if nsText.substring(with: nextRange) == "–" {
                    MarkdownLists.performEdit(textView, replace: nextRange, with: "—")
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }
        }

        // En-dash auto-format: ` - <space>` → ` – <space>`. Triggers on the
        // SECOND space (the one after the `-`). Skipped when the line has only
        // whitespace before the `-` (preserves top-level + nested bullets),
        // inside fenced/inline code, or inside an open `[[...]]` wikilink
        // target where ` - ` may appear in a filename.
        if replacementString == " " && affectedCharRange.length == 0 && !isInCodeBlock {
            // Checkbox shorthand → GFM canonicalization. When the caret sits
            // right after a bare `-[]` / `-[ ]` / `-[x]` marker (no space
            // between the bullet and the bracket) and the user types the space
            // that starts the content, rewrite the marker to portable GFM
            // (`- [ ] ` / `- [x] `) and consume the typed space. Keeps the fast
            // shorthand input but writes Obsidian-renderable source, matching
            // Enter-continuation's output. The caret lands AFTER the trailing
            // space so typing flows straight into the content — the space feels
            // like it simply "expanded" the marker.
            if listsEnabled {
                let nsText = textView.string as NSString
                let caret = affectedCharRange.location
                let lineStart = nsText.lineRange(for: NSRange(location: caret, length: 0)).location
                let upToCaret = nsText.substring(
                    with: NSRange(location: lineStart, length: caret - lineStart))
                let scanRange = NSRange(location: 0, length: (upToCaret as NSString).length)
                if let m = shorthandCheckboxRegex.firstMatch(in: upToCaret, range: scanRange) {
                    let up = upToCaret as NSString
                    let ws = up.substring(with: m.range(at: 1))
                    let marker = up.substring(with: m.range(at: 2))
                    let inner = up.substring(with: m.range(at: 3))
                    let box = inner.lowercased() == "x" ? "x" : " "
                    let gfm = "\(ws)\(marker) [\(box)] "
                    MarkdownLists.performEdit(
                        textView,
                        replace: NSRange(location: lineStart, length: caret - lineStart),
                        with: gfm)
                    textView.setSelectedRange(
                        NSRange(location: lineStart + (gfm as NSString).length, length: 0))
                    return false
                }
            }

            let insertionLocation = affectedCharRange.location
            if insertionLocation >= 2 {
                let nsText = textView.string as NSString
                let dashPosition = insertionLocation - 1
                let prev1 = nsText.substring(with: NSRange(location: dashPosition, length: 1))
                let prev2 = nsText.substring(with: NSRange(location: insertionLocation - 2, length: 1))
                if prev1 == "-" && prev2 == " " {
                    let lineStart = nsText.lineRange(
                        for: NSRange(location: insertionLocation, length: 0)
                    ).location
                    if dashPosition > lineStart {
                        let beforeDash = nsText.substring(
                            with: NSRange(location: lineStart, length: dashPosition - lineStart)
                        )
                        let hasContent = beforeDash.contains { !$0.isWhitespace }
                        if hasContent,
                            !MarkdownDetection.isInsideWikilink(
                                location: insertionLocation, in: textView.string
                            )
                        {
                            let replaceRange = NSRange(location: dashPosition, length: 1)
                            MarkdownLists.performEdit(textView, replace: replaceRange, with: "– ")
                            textView.setSelectedRange(
                                NSRange(location: insertionLocation + 1, length: 0)
                            )
                            return false
                        }
                    }
                }
            }
        }

        // Autocomplete Obsidian-style node brackets and single square brackets
        if replacementString == "[" {
            let nsText = textView.string as NSString
            let insertionLocation = affectedCharRange.location
            if insertionLocation > 0 {
                let prevChar = nsText.substring(with: NSRange(location: insertionLocation - 1, length: 1))
                if prevChar == "[" {
                    let hasAutoCloseBracket =
                        insertionLocation < nsText.length
                        && nsText.substring(with: NSRange(location: insertionLocation, length: 1)) == "]"
                    if hasAutoCloseBracket {
                        // Collapse auto-paired "[]" into "[[]]" without changing surrounding text.
                        MarkdownLists.performEdit(
                            textView,
                            replace: NSRange(location: insertionLocation - 1, length: 2),
                            with: "[[]]"
                        )
                    } else {
                        // If the char to the right is not "]" (e.g. newline), do not delete it.
                        MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "[]]")
                    }
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }
            guard autoClosePairsEnabled else { return true }
            // Only auto-pair single `[` when the preceding char is whitespace
            // or the cursor is at the start of the document/line. This keeps
            // the Pommora `-[]` task-list shorthand fluid (`-[` doesn't get
            // auto-paired, so the user can type the literal `[]` and then
            // continue with space + content). Auto-pair still fires for the
            // common prose-link case (e.g. `text [link](url)`) where `[`
            // follows a space, and at line start.
            let shouldAutoPair: Bool
            if insertionLocation == 0 {
                shouldAutoPair = true
            } else {
                let prevChar = nsText.substring(
                    with: NSRange(location: insertionLocation - 1, length: 1))
                shouldAutoPair = prevChar == " " || prevChar == "\t" || prevChar == "\n"
            }
            guard shouldAutoPair else { return true }
            return insertAutoPair(open: "[", close: "]")
        }

        // Autocomplete parentheses / braces
        if replacementString == "(" || replacementString == "{" {
            guard autoClosePairsEnabled else { return true }
            let closeChar = (replacementString == "(") ? ")" : "}"
            return insertAutoPair(open: replacementString, close: closeChar)
        }

        // TAB: indent list items (skip in code blocks)
        if replacementString == "\t" && !isInCodeBlock {
            guard listsEnabled else { return true }
            let nsText = textView.string as NSString
            let insertionLocation = affectedCharRange.location
            let safeLocTAB = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: safeLocTAB, length: 0))
            let currentLine = nsText.substring(with: currentLineRange)
            if MarkdownLists.listRegex.firstMatch(
                in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) != nil
            {
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(
                    in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count))
                {
                    let ws = (currentLine as NSString).substring(with: wsMatch.range)
                    let level = MarkdownLists.indentLevel(from: ws)
                    if level >= MarkdownPMConfiguration.default.lists.maximumNestingLevel {
                        return false
                    }
                }
                MarkdownLists.performEdit(
                    textView, replace: NSRange(location: currentLineRange.location, length: 0), with: "\t")
                textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                return false
            }
            if MarkdownLists.dashNoSpaceRegex.firstMatch(
                in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) != nil
            {
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(
                    in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count))
                {
                    let ws = (currentLine as NSString).substring(with: wsMatch.range)
                    let level = MarkdownLists.indentLevel(from: ws)
                    if level >= MarkdownPMConfiguration.default.lists.maximumNestingLevel { return false }
                }
                MarkdownLists.performEdit(
                    textView, replace: NSRange(location: currentLineRange.location, length: 0), with: "\t")
                textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                return false
            }
            return true
        }

        // ENTER: list continuation/outdent + code-block completion.
        //
        // Legacy HR expansion removed (Pommora HR dynamic-syntax plan,
        // Session 12 — 2026-05-20). The prior behavior replaced `---` with a
        // visible-width-wide string of dashes on Enter, mutating the source
        // text. The new approach keeps `---` as 3 chars in storage and renders
        // a horizontal line via custom NSTextLayoutFragment drawing only when
        // the caret has left the paragraph (see MarkdownTextLayoutFragment
        // `drawThematicBreak` + `NativeTextViewCoordinator+HRVisibility`). The
        // legacy expansion conflicted directly with this — it inflated the
        // source to ~100 dashes, breaking the canonical text storage and
        // producing the "auto-adds physical dashes" + "line-to-line HRs
        // render invisible" bugs Nathan observed.
        if replacementString == "\n" {
            // Shift+Enter intercept. macOS's default key binding maps both
            // plain Return and Shift+Return to `insertNewline:` (the `doCommandBy`
            // `insertLineBreak:` selector only fires on Ctrl+\). We distinguish
            // here via the current keyboard event's modifier flags. Shift held
            // → plain `\n` (hard exit / consistent soft newline), skip all list
            // AND blockquote continuation logic. Shift released → fall through
            // to the list / blockquote handlers below (plain Enter continues
            // both lists and blockquotes; Shift+Enter exits both).
            if let event = NSApp.currentEvent,
                event.type == .keyDown,
                event.modifierFlags.contains(.shift)
            {
                MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "\n")
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                return false
            }

            let nsText = textView.string as NSString
            let safeLocENTER = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: safeLocENTER, length: 0))
            let currentLine = nsText.substring(with: currentLineRange).trimmingCharacters(in: .whitespacesAndNewlines)

            // Bracket-skip: when the caret sits between a matched open/close
            // pair on the current line, Enter jumps past the closer instead
            // of inserting `\n`. Mirrors the VS Code "Tab to escape brackets"
            // pattern, mapped to Enter. Position-based (no auto-pair state
            // tracking) so it works for both auto-paired and manually-typed
            // or pasted brackets. Gated by `autoClosePairsEnabled` so users
            // who disabled auto-pair keep full control over Enter.
            //
            // Carve-out: when the matched opener is part of the list-marker
            // checkbox (e.g. `-[x|]` / `- [x|]`), fall through to list-Enter
            // so the user can continue the list from inside the brackets.
            //
            // Obsidian `[[ ]]` double-jump: both `[[` behind AND `]]` ahead
            // → jump past both `]]`. Requires both to avoid mis-detecting
            // pathological strings like `[a]] caret` as wikilinks.
            if autoClosePairsEnabled && affectedCharRange.length == 0 && !isInCodeBlock {
                let lineEnd = currentLineRange.location + currentLineRange.length
                let hasTrailingNewline =
                    currentLineRange.length > 0
                    && nsText.character(at: lineEnd - 1) == 10  // '\n'
                let lineContentEnd = hasTrailingNewline ? lineEnd - 1 : lineEnd

                let openSquare: unichar = 0x5B  // [
                let closeSquare: unichar = 0x5D  // ]
                let openParen: unichar = 0x28  // (
                let closeParen: unichar = 0x29  // )
                let openBrace: unichar = 0x7B  // {
                let closeBrace: unichar = 0x7D  // }

                // Forward scan: nearest `]`, `)`, or `}` ahead on this line.
                var foundCloserLoc = -1
                var foundCloserChar: unichar = 0
                var scan = safeLocENTER
                while scan < lineContentEnd {
                    let c = nsText.character(at: scan)
                    if c == closeSquare || c == closeParen || c == closeBrace {
                        foundCloserLoc = scan
                        foundCloserChar = c
                        break
                    }
                    scan += 1
                }

                if foundCloserLoc >= 0 {
                    let opener: unichar
                    switch foundCloserChar {
                    case closeSquare: opener = openSquare
                    case closeParen: opener = openParen
                    case closeBrace: opener = openBrace
                    default: opener = openSquare
                    }
                    // Backward scan: nearest matching opener behind caret.
                    var openerLoc = -1
                    var back = safeLocENTER - 1
                    while back >= currentLineRange.location {
                        if nsText.character(at: back) == opener {
                            openerLoc = back
                            break
                        }
                        back -= 1
                    }

                    if openerLoc >= 0 {
                        // Carve-out: opener lies inside the list-marker zone
                        // (i.e. it's the `[` of a `-[x]` / `- [x]` checkbox).
                        var isCheckboxBracket = false
                        let lineContentLen = lineContentEnd - currentLineRange.location
                        let lineRaw = nsText.substring(
                            with: NSRange(location: currentLineRange.location, length: lineContentLen))
                        if let listMatch = MarkdownLists.listRegex.firstMatch(
                            in: lineRaw,
                            range: NSRange(location: 0, length: lineRaw.utf16.count))
                        {
                            let markerCapture = listMatch.range(at: 1)
                            let markerEnd = markerCapture.location + markerCapture.length
                            let openerLineOffset = openerLoc - currentLineRange.location
                            if openerLineOffset < markerEnd {
                                isCheckboxBracket = true
                            }
                        }

                        if !isCheckboxBracket {
                            // Default: jump past the single closer.
                            var jumpToLoc = foundCloserLoc + 1
                            // Obsidian double-jump: require both `[[` and `]]`.
                            if foundCloserChar == closeSquare,
                                foundCloserLoc + 1 < lineContentEnd,
                                nsText.character(at: foundCloserLoc + 1) == closeSquare,
                                openerLoc > currentLineRange.location,
                                nsText.character(at: openerLoc - 1) == openSquare
                            {
                                jumpToLoc = foundCloserLoc + 2
                            }
                            textView.setSelectedRange(NSRange(location: jumpToLoc, length: 0))
                            return false
                        }
                    }
                }
            }

            if currentLine.range(of: "^```\\w*$", options: .regularExpression) != nil {
                let textBeforeLine = nsText.substring(to: currentLineRange.location)
                let openingCount = textBeforeLine.components(separatedBy: "```").count - 1
                let afterLineStart = currentLineRange.location + currentLineRange.length
                let hasClosingAfter: Bool = {
                    guard afterLineStart < nsText.length else { return false }
                    return nsText.substring(from: afterLineStart).contains("```")
                }()
                let lineEnd = currentLineRange.location + max(0, currentLineRange.length - 1)
                let cursorAtLineEnd = affectedCharRange.location >= lineEnd

                if openingCount.isMultiple(of: 2) && cursorAtLineEnd && !hasClosingAfter {
                    let insertionLocation = affectedCharRange.location
                    let completion = "\n\n```"
                    MarkdownLists.performEdit(textView, replace: affectedCharRange, with: completion)
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }

            // Blockquote continuation. Plain Enter on a `> ...` line inserts
            // `\n<prefix>` where <prefix> is the captured leading whitespace +
            // `> ` so nested-indent quotes preserve their depth. Matches list
            // convention: plain Enter continues, Shift+Enter (intercepted at
            // the top of the `\n` block) exits. No-op when there's a selection
            // or the caret is inside a fenced code block.
            if affectedCharRange.length == 0 && !isInCodeBlock {
                let rawCurrentLine = nsText.substring(with: currentLineRange)
                if let match = MarkdownLists.blockquoteMarkerRegex.firstMatch(
                    in: rawCurrentLine,
                    range: NSRange(location: 0, length: rawCurrentLine.utf16.count))
                {
                    let prefix = (rawCurrentLine as NSString).substring(with: match.range)
                    let insertion = "\n\(prefix)"
                    MarkdownLists.performEdit(textView, replace: affectedCharRange, with: insertion)
                    textView.setSelectedRange(
                        NSRange(location: affectedCharRange.location + insertion.utf16.count, length: 0))
                    return false
                }
            }

            // Skip list logic in code blocks + when text is selected.
            guard listsEnabled && !isInCodeBlock else { return true }
            guard affectedCharRange.length == 0 else { return true }

            guard
                let ctx = MarkdownLists.detectListContext(
                    in: textView,
                    caretLocation: affectedCharRange.location,
                    isInCodeBlock: isInCodeBlock
                )
            else { return true }

            // Edge guard: caret in marker zone or BEFORE the marker (line offset
            // below content-start). Let AppKit insert plain `\n`. Fixes the
            // "voids the line at caret-line-start" regression — pressing Enter
            // at line start now inserts `\n` above and pushes the list item down.
            let caretOffsetInLine = affectedCharRange.location - ctx.lineRange.location
            guard caretOffsetInLine >= ctx.contentStartOffsetInLine else { return true }

            // ── Case 1: List-start trigger (bare "-" or "1." + Enter) ─────────
            // The user typed a bare marker and pressed Enter. Complete the
            // marker on the current line (append " ") and insert the next bullet
            // on a new line below. CommonMark parses `- \n- ` as a 2-item list.
            if ctx.isBareStartTrigger {
                let markerOnNewLine: String
                switch ctx.kind {
                case .unordered(let ch):
                    markerOnNewLine = "\(ch) "
                case .ordered(let n):
                    markerOnNewLine = "\(n + 1). "
                }
                let suffix = " \n\(ctx.leadingWhitespace)\(markerOnNewLine)"
                MarkdownLists.performEdit(textView, replace: affectedCharRange, with: suffix)
                let cursorPos = affectedCharRange.location + suffix.utf16.count
                textView.setSelectedRange(NSRange(location: cursorPos, length: 0))
                return false
            }

            // ── Case 2: Enter (end-of-line OR mid-line OR empty) → next list item ─
            // Single behavior for all in-list Enter cases: insert a new list
            // item with the matching marker. For mid-line, text after the caret
            // naturally splits to the new item. For empty `- ` items, this
            // creates another empty `- ` below — exit is via Shift+Enter only.
            let newItem: String
            switch ctx.kind {
            case .unordered(let ch):
                newItem =
                    ctx.hasCheckbox
                    ? "\n\(ctx.leadingWhitespace)\(ch) [ ] "
                    : "\n\(ctx.leadingWhitespace)\(ch) "
            case .ordered(let n):
                newItem =
                    ctx.hasCheckbox
                    ? "\n\(ctx.leadingWhitespace)\(n + 1). [ ] "
                    : "\n\(ctx.leadingWhitespace)\(n + 1). "
            }
            MarkdownLists.performEdit(textView, replace: affectedCharRange, with: newItem)
            let cursorPos = affectedCharRange.location + newItem.utf16.count
            textView.setSelectedRange(NSRange(location: cursorPos, length: 0))
            return false
        }

        return true
    }
}
