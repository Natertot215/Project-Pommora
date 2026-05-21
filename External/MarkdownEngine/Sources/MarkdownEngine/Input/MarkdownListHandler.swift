//
//  MarkdownListHandler.swift
//  MarkdownEngine
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

        if let coord = textView.delegate as? NativeTextViewWrapper.Coordinator { coord.isProgrammaticEdit = true }
        defer {
            if let coord = textView.delegate as? NativeTextViewWrapper.Coordinator { coord.isProgrammaticEdit = false }
        }

        guard textView.shouldChangeText(in: safeRange, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: safeRange, with: string)
        textView.didChangeText()
    }

    static let listRegex = try! NSRegularExpression(
        pattern: #"^\s*((?:(\d+)\.|[-•])(?:\s+\[[ xX]\])?\s+)"#
    )
    static let dashNoSpaceRegex = try! NSRegularExpression(pattern: #"^\s*-(?!\s)"#)
    static let leadingWhitespaceRegex = try! NSRegularExpression(pattern: #"^\s*"#)
    static let bareMarkerRegex = try! NSRegularExpression(pattern: #"^\s*([-*+]|\d+\.)\s*$"#)

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
        configuration: MarkdownEditorConfiguration = .default
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

                ps.tabStops = []
                ps.defaultTabInterval = indentPerLevel
                // Default visual indent (one tab-stop from page margin) on top
                // of any source-level nesting captured in depthIndent. Restores
                // the visual breathing room the pre-v0.2.7.3 `\t• ` rewrite
                // provided automatically — without putting `\t` chars in the
                // canonical source.
                ps.firstLineHeadIndent = indentPerLevel + depthIndent
                ps.headIndent = indentPerLevel + depthIndent + markerWidth + extraSpacing

                attributesList.append((match.range(at: 0), [.paragraphStyle: ps]))
            }
        }

        // Ordered lists
        let orderedListPattern = #"^([ \t]*)(\d+\.(?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#
        if let orderedListRegex = try? NSRegularExpression(pattern: orderedListPattern, options: [.anchorsMatchLines]) {
            applyListMatches(orderedListRegex.matches(in: text, options: [], range: fullRange))
        }

        // Bullet lists. Accepts `-`, `*`, `+` (CommonMark) and `•` (legacy Pommora).
        let bulletListPattern = #"^([ \t]*)([-*+•](?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#
        if let bulletListRegex = try? NSRegularExpression(pattern: bulletListPattern, options: [.anchorsMatchLines]) {
            applyListMatches(bulletListRegex.matches(in: text, options: [], range: fullRange))
        }
        return attributesList
    }

    // MARK: - Input Handling

    static func handleInsertion(textView: NSTextView, affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return true }

        // Fast path: skip the expensive isInsideCodeBlock scan for ordinary typing.
        if replacementString.count == 1,
            let ch = replacementString.first,
            ch != ">" && ch != "[" && ch != "(" && ch != "{" && ch != "\t" && ch != " " && ch != "\n"
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
            if previousChar == "-" {
                MarkdownLists.performEdit(textView, replace: previousCharRange, with: "→")
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return false
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
                    if level >= MarkdownEditorConfiguration.default.lists.maximumNestingLevel {
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
                    if level >= MarkdownEditorConfiguration.default.lists.maximumNestingLevel { return false }
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
            // logic. Shift released → fall through to the list handler below.
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
