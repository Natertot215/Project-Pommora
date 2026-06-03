//
//  ContextMenu.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 20.06.25.
//
//  Right-click menu with toggleable Markdown formatting actions.
//

import Cocoa
import SwiftUI

extension MarkdownPMEditor.Coordinator {
    public func textView(
        _ textView: NSTextView,
        menu: NSMenu,
        for event: NSEvent,
        at charIndex: Int
    ) -> NSMenu? {
        let customMenu = menu.copy() as? NSMenu ?? NSMenu()

        if let fontIndex = customMenu.items.firstIndex(where: { $0.title == "Font" }) {
            customMenu.removeItem(at: fontIndex)

            // Format submenu — inline marks
            let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
            let formatSubmenu = NSMenu(title: "Format")
            let formatSpecs: [(String, Selector)] = [
                ("Bold", #selector(didMarkdownBold(_:))),
                ("Italic", #selector(didMarkdownItalic(_:))),
                ("Strikethrough", #selector(didMarkdownStrikethrough(_:))),
                ("Inline Code", #selector(didMarkdownInlineCode(_:))),
                ("Link", #selector(didMarkdownLink(_:))),
            ]
            for (title, selector) in formatSpecs {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = self
                formatSubmenu.addItem(item)
            }
            formatItem.submenu = formatSubmenu
            customMenu.insertItem(formatItem, at: fontIndex)

            // Heading submenu — H1 through H4. H5/H6 omitted because they
            // render smaller than body text at typical Pommora font scales.
            let headingItem = NSMenuItem(title: "Heading", action: nil, keyEquivalent: "")
            let headingSubmenu = NSMenu(title: "Heading")
            for level in 1...4 {
                let item = NSMenuItem(title: "H\(level)", action: #selector(didMarkdownHeading(_:)), keyEquivalent: "")
                item.target = self
                item.tag = level
                headingSubmenu.addItem(item)
            }
            headingItem.submenu = headingSubmenu
            customMenu.insertItem(headingItem, at: fontIndex + 1)

            // Lists submenu — Bullet, Numbered
            let listItem = NSMenuItem(title: "Lists", action: nil, keyEquivalent: "")
            let listSubmenu = NSMenu(title: "Lists")
            let unorderedItem = NSMenuItem(
                title: "Bullet", action: #selector(didMarkdownUnorderedList(_:)), keyEquivalent: "")
            unorderedItem.target = self
            listSubmenu.addItem(unorderedItem)
            let orderedItem = NSMenuItem(
                title: "Numbered", action: #selector(didMarkdownOrderedList(_:)), keyEquivalent: "")
            orderedItem.target = self
            listSubmenu.addItem(orderedItem)
            listItem.submenu = listSubmenu
            customMenu.insertItem(listItem, at: fontIndex + 2)

            // Block submenu — block-level inserts (Blockquote, Code Block,
            // Table, Horizontal Rule). Distinct from Format (inline marks)
            // because these all create or transform full blocks.
            let blockItem = NSMenuItem(title: "Block", action: nil, keyEquivalent: "")
            let blockSubmenu = NSMenu(title: "Block")
            let blockSpecs: [(String, Selector)] = [
                ("Blockquote", #selector(didMarkdownBlockquote(_:))),
                ("Code Block", #selector(didMarkdownCodeBlock(_:))),
                ("Table", #selector(didMarkdownTable(_:))),
                ("Horizontal Rule", #selector(didMarkdownHorizontalRule(_:))),
            ]
            for (title, selector) in blockSpecs {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = self
                blockSubmenu.addItem(item)
            }
            blockItem.submenu = blockSubmenu
            customMenu.insertItem(blockItem, at: fontIndex + 3)

            customMenu.insertItem(NSMenuItem.separator(), at: fontIndex + 4)
        }

        return customMenu
    }

    // MARK: - Inline format handlers (Pommora additions)

    @objc func didMarkdownStrikethrough(_ sender: Any?) {
        guard let tv = textView else { return }
        if tv.selectedRange().length == 0 {
            insertEmptyMarkers("~~")
        } else {
            wrapSelection(with: "~~")
        }
    }

    @objc func didMarkdownInlineCode(_ sender: Any?) {
        guard let tv = textView else { return }
        if tv.selectedRange().length == 0 {
            insertEmptyMarkers("`")
        } else {
            wrapSelection(with: "`")
        }
    }

    /// Wraps selection (or inserts at caret) as `[text](url)`. If selection
    /// is empty, places caret in the `text` slot. If non-empty, treats the
    /// selection as link text and places caret in the URL slot.
    @objc func didMarkdownLink(_ sender: Any?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let nsText = tv.string as NSString
        let insertion: String
        let cursorOffset: Int
        let cursorLen: Int
        if range.length == 0 {
            insertion = "[](url)"
            cursorOffset = 1  // between `[` and `]`
            cursorLen = 0
        } else {
            let selectedText = nsText.substring(with: range)
            insertion = "[\(selectedText)](url)"
            // Caret lands on the "url" placeholder, selected.
            cursorOffset = 1 + selectedText.utf16.count + 2  // skip `[text](`
            cursorLen = 3  // select "url"
        }
        if tv.shouldChangeText(in: range, replacementString: insertion) {
            tv.replaceCharacters(in: range, with: insertion)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + cursorOffset, length: cursorLen))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    // MARK: - Block format handlers (Pommora additions)

    /// Prefixes each line in the selection (or the current line if none) with
    /// `> ` to make a blockquote.
    @objc func didMarkdownBlockquote(_ sender: Any?) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let selRange = tv.selectedRange()
        // Expand to full line(s) so prefixing applies cleanly.
        let blockRange = nsText.lineRange(for: selRange)
        let original = nsText.substring(with: blockRange)
        // Split + prefix each line. Trailing empty after final \n preserved.
        let lines = original.components(separatedBy: "\n")
        let prefixed = lines.enumerated().map { idx, line -> String in
            // Last element is "" when original ends with \n; don't prefix that.
            if idx == lines.count - 1 && line.isEmpty { return line }
            return "> " + line
        }
        let replacement = prefixed.joined(separator: "\n")
        if tv.shouldChangeText(in: blockRange, replacementString: replacement) {
            tv.replaceCharacters(in: blockRange, with: replacement)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: blockRange.location, length: replacement.utf16.count))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    /// Wraps selection (or inserts at caret) in a fenced code block.
    @objc func didMarkdownCodeBlock(_ sender: Any?) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let selectedText = range.length == 0 ? "" : nsText.substring(with: range)
        let prefix = needsLeadingNewline(at: range.location, in: nsText) ? "\n```\n" : "```\n"
        let suffix = "\n```"
        let insertion = prefix + selectedText + suffix
        if tv.shouldChangeText(in: range, replacementString: insertion) {
            tv.replaceCharacters(in: range, with: insertion)
            tv.didChangeText()
            // Caret lands inside the fenced block on the content line.
            let caret = range.location + prefix.utf16.count + selectedText.utf16.count
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    /// Inserts a 3-column × 2-row table scaffold at the cursor (the header
    /// row plus the alignment row plus a single data row). User fills cells.
    @objc func didMarkdownTable(_ sender: Any?) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let leadingNewline = needsLeadingNewline(at: range.location, in: nsText) ? "\n" : ""
        let scaffold = """
            | Header 1 | Header 2 | Header 3 |
            |----------|----------|----------|
            | Cell     | Cell     | Cell     |
            """
        let insertion = leadingNewline + scaffold + "\n"
        if tv.shouldChangeText(in: range, replacementString: insertion) {
            tv.replaceCharacters(in: range, with: insertion)
            tv.didChangeText()
            // Caret lands at start of "Header 1" so the user can immediately
            // type to overwrite the first header. Offset = leading newline +
            // "| " (2 chars).
            let caret = range.location + leadingNewline.utf16.count + 2
            tv.setSelectedRange(NSRange(location: caret, length: 8))  // selects "Header 1"
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    /// Inserts `\n---\n` (ThematicBreak) on its own line at the cursor.
    @objc func didMarkdownHorizontalRule(_ sender: Any?) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let leadingNewline = needsLeadingNewline(at: range.location, in: nsText) ? "\n" : ""
        let insertion = leadingNewline + "---\n"
        if tv.shouldChangeText(in: range, replacementString: insertion) {
            tv.replaceCharacters(in: range, with: insertion)
            tv.didChangeText()
            let caret = range.location + insertion.utf16.count
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    /// True when inserting at `location` would NOT start on a fresh line.
    /// Used by block-level inserts (Code Block, Table, HR) so they always
    /// land on their own line rather than appended to whatever the caret
    /// was sitting in the middle of.
    private func needsLeadingNewline(at location: Int, in nsText: NSString) -> Bool {
        guard location > 0 else { return false }
        let prevChar = nsText.character(at: location - 1)
        return prevChar != 0x0A  // not a newline
    }

    /// Returns the smallest bold or boldItalic token that fully contains the selection, or nil when the selection isn't enclosed by emphasis with a bold trait.
    func enclosingBoldToken(for selection: NSRange, in text: String) -> MarkdownToken? {
        let tokens = parsedDocument(for: text).tokens
        return tokens.first { token in
            (token.kind == .bold || token.kind == .boldItalic) && tokenEncloses(token, selection: selection)
        }
    }

    /// Returns the smallest italic or boldItalic token that fully contains the selection, or nil when the selection isn't enclosed by emphasis with an italic trait.
    func enclosingItalicToken(for selection: NSRange, in text: String) -> MarkdownToken? {
        let tokens = parsedDocument(for: text).tokens
        return tokens.first { token in
            (token.kind == .italic || token.kind == .boldItalic) && tokenEncloses(token, selection: selection)
        }
    }

    func isSelectionBold(in nsText: NSString, range: NSRange) -> Bool {
        return enclosingBoldToken(for: range, in: nsText as String) != nil
    }

    func isSelectionItalic(in nsText: NSString, range: NSRange) -> Bool {
        return enclosingItalicToken(for: range, in: nsText as String) != nil
    }

    private func tokenEncloses(_ token: MarkdownToken, selection: NSRange) -> Bool {
        return selection.location >= token.range.location
            && NSMaxRange(selection) <= NSMaxRange(token.range)
    }

    /// Replaces the marker characters of an emphasis token with `replacement` on each side, preserving the inner content.
    private func unwrapToken(_ token: MarkdownToken, leftReplacement: String, rightReplacement: String) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let content = nsText.substring(with: token.contentRange)
        let newText = leftReplacement + content + rightReplacement
        if tv.shouldChangeText(in: token.range, replacementString: newText) {
            tv.replaceCharacters(in: token.range, with: newText)
            tv.didChangeText()
            let newSelectionLocation = token.range.location + leftReplacement.count
            tv.setSelectedRange(NSRange(location: newSelectionLocation, length: content.count))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    func isSelectionHeading(level: Int, in nsText: NSString, range: NSRange) -> Bool {
        let lineRange = nsText.lineRange(for: range)
        let line = nsText.substring(with: lineRange)
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine.hasPrefix(String(repeating: "#", count: level) + " ")
    }

    func isSelectionList(in nsText: NSString, range: NSRange) -> Bool {
        let lineRange = nsText.lineRange(for: range)
        let line = nsText.substring(with: lineRange)
        // CommonMark bullets, legacy `\t• `, or any ordered marker.
        return line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
            || line.hasPrefix("\t• ")
            || line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    private func applyHeading(level: Int) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let lineRange = nsText.lineRange(for: range)
        let rawLine = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        var content = rawLine
        while content.hasPrefix("#") { content.removeFirst() }
        content = content.trimmingCharacters(in: .whitespaces)
        let prefix = String(repeating: "#", count: level) + " "
        let newLine = prefix + content
        if tv.shouldChangeText(in: lineRange, replacementString: newLine) {
            tv.replaceCharacters(in: lineRange, with: newLine)
            tv.didChangeText()
            let newSel = NSRange(location: lineRange.location + prefix.count, length: content.count)
            tv.setSelectedRange(newSel)
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    @objc func didMarkdownHeading(_ sender: NSMenuItem) {
        applyHeading(level: sender.tag)
    }

    private func applyList(prefix: String) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let selRange = tv.selectedRange()
        let startLine = nsText.lineRange(for: selRange)
        let originalLine = nsText.substring(with: startLine)
        let lineText = originalLine.trimmingCharacters(in: .newlines)
        var content = lineText
        // Strip any existing list-marker prefix before adding the new one —
        // covers legacy `\t• ` and CommonMark variants so toggling between
        // unordered/ordered doesn't double-prefix.
        let knownPrefixes = ["\t• ", "- ", "* ", "+ "]
        for p in knownPrefixes where content.hasPrefix(p) {
            content = String(content.dropFirst(p.count))
            break
        }
        if let match = content.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            content = String(content[match.upperBound...])
        }
        let newLine = prefix + content
        let suffix = originalLine.hasSuffix("\n") ? "\n" : ""
        let replacement = newLine + suffix
        if tv.shouldChangeText(in: startLine, replacementString: replacement) {
            tv.replaceCharacters(in: startLine, with: replacement)
            tv.didChangeText()
            let newSel = NSRange(location: startLine.location + prefix.count, length: content.count)
            tv.setSelectedRange(newSel)
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    @objc func didMarkdownUnorderedList(_ sender: Any?) {
        applyList(prefix: "- ")
    }

    @objc func didMarkdownOrderedList(_ sender: Any?) {
        applyList(prefix: "1. ")
    }

    @objc func didMarkdownBold(_ sender: Any?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        if let token = enclosingBoldToken(for: range, in: tv.string) {
            // Toggle off: bold → plain, boldItalic → italic.
            let (left, right) = token.kind == .boldItalic ? ("*", "*") : ("", "")
            unwrapToken(token, leftReplacement: left, rightReplacement: right)
            return
        }

        if range.length == 0 {
            insertEmptyMarkers("**")
            return
        }

        wrapSelection(with: "**")
    }

    @objc func didMarkdownItalic(_ sender: Any?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        if let token = enclosingItalicToken(for: range, in: tv.string) {
            // Toggle off: italic → plain, boldItalic → bold.
            let (left, right) = token.kind == .boldItalic ? ("**", "**") : ("", "")
            unwrapToken(token, leftReplacement: left, rightReplacement: right)
            return
        }

        if range.length == 0 {
            insertEmptyMarkers("*")
            return
        }

        wrapSelection(with: "*")
    }

    private func insertEmptyMarkers(_ marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let insertion = marker + marker
        if tv.shouldChangeText(in: range, replacementString: insertion) {
            tv.replaceCharacters(in: range, with: insertion)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + marker.count, length: 0))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    private func wrapSelection(with marker: String) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let original = nsText.substring(with: range)
        let leadingWS = original.prefix { $0.isWhitespace }.count
        let trailingWS = original.reversed().prefix { $0.isWhitespace }.count
        let coreStart = original.index(original.startIndex, offsetBy: leadingWS)
        let coreEnd = original.index(original.endIndex, offsetBy: -trailingWS)
        let core = coreStart <= coreEnd ? String(original[coreStart..<coreEnd]) : ""
        let leading = String(original[..<coreStart])
        let trailing = String(original[coreEnd...])
        let newText = leading + marker + core + marker + trailing
        if tv.shouldChangeText(in: range, replacementString: newText) {
            tv.replaceCharacters(in: range, with: newText)
            tv.didChangeText()
            let newRange = NSRange(location: range.location + leadingWS + marker.count, length: core.count)
            tv.setSelectedRange(newRange)
            DispatchQueue.main.async { self.text = tv.string }
        }
    }
}

// MARK: - Menu Item Validation
extension MarkdownPMEditor.Coordinator: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let tv = textView else { return true }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        switch menuItem.action {
        case #selector(didMarkdownBold(_:)):
            menuItem.state = enclosingBoldToken(for: range, in: tv.string) != nil ? .on : .off
            return true
        case #selector(didMarkdownItalic(_:)):
            menuItem.state = enclosingItalicToken(for: range, in: tv.string) != nil ? .on : .off
            return true
        case #selector(didMarkdownHeading(_:)):
            return !isSelectionHeading(level: menuItem.tag, in: nsText, range: range)
        case #selector(didMarkdownUnorderedList(_:)),
            #selector(didMarkdownOrderedList(_:)):
            return !isSelectionList(in: nsText, range: range)
        default:
            return true
        }
    }
}
