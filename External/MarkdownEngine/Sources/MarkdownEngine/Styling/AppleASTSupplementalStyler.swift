//
//  AppleASTSupplementalStyler.swift
//  MarkdownEngine
//
//  Walks Apple swift-markdown's Document AST to apply styling for
//  Markdown constructs the engine's regex tokenizer doesn't cover:
//  BlockQuote, Strikethrough, Table, ThematicBreak. Runs AFTER the
//  primary MarkdownStyler pass so it composes additively — primary
//  styler handles emphasis/links/code/lists/headings, this pass adds
//  the GFM-and-extended block types Pommora needs.
//
//  Pommora-owned addition to the vendored engine (Session 9 follow-up).
//

import AppKit
import Foundation
import Markdown

@MainActor
enum AppleASTSupplementalStyler {

    /// Walk Apple's AST and emit attributes for BlockQuote / Strikethrough
    /// / Table / ThematicBreak. Returns ranges to apply on top of the
    /// primary styler's output.
    static func styleAttributes(
        text: String,
        baseFont: NSFont,
        theme: MarkdownEditorTheme
    ) -> [StyledRange] {
        let document = Document(parsing: text)
        let nsText = text as NSString
        let lineIndex = LineOffsetIndex(text: text)
        var visitor = Visitor(
            nsText: nsText,
            lineIndex: lineIndex,
            baseFont: baseFont,
            theme: theme
        )
        visitor.visit(document)
        return visitor.styledRanges
    }

    private struct Visitor: MarkupVisitor {
        typealias Result = Void

        let nsText: NSString
        let lineIndex: LineOffsetIndex
        let baseFont: NSFont
        let theme: MarkdownEditorTheme
        var styledRanges: [StyledRange] = []

        mutating func defaultVisit(_ markup: any Markup) {
            for child in markup.children {
                visit(child)
            }
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            if let range = SourceRangeConverter.nsRange(from: blockQuote.range, in: nsText, lineIndex: lineIndex) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.headIndent = 20
                paragraph.firstLineHeadIndent = 20
                styledRanges.append(
                    (
                        range,
                        [
                            .foregroundColor: theme.bodyText.withAlphaComponent(0.75),
                            .backgroundColor: theme.bodyText.withAlphaComponent(0.06),
                            .paragraphStyle: paragraph,
                        ]
                    ))
            }
            // Continue walking children so nested strikethrough etc. still fire.
            for child in blockQuote.children {
                visit(child)
            }
        }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
            if let range = SourceRangeConverter.nsRange(from: strikethrough.range, in: nsText, lineIndex: lineIndex) {
                styledRanges.append(
                    (
                        range,
                        [
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: theme.bodyText,
                        ]
                    ))
            }
            for child in strikethrough.children {
                visit(child)
            }
        }

        mutating func visitTable(_ table: Table) {
            guard let tableRange = SourceRangeConverter.nsRange(from: table.range, in: nsText, lineIndex: lineIndex)
            else {
                return
            }
            // Cell content uses monospace + faint bg tint so columns align.
            let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            styledRanges.append(
                (
                    tableRange,
                    [
                        .font: monoFont,
                        .backgroundColor: theme.bodyText.withAlphaComponent(0.04),
                    ]
                ))

            // Hide all `|` cell separators across the table's range — they
            // become invisible while staying in source for canonical-md
            // preservation.
            let hiddenFont = NSFont.systemFont(ofSize: 0.1)
            let tableText = nsText.substring(with: tableRange)
            var searchStart = tableText.startIndex
            while let pipeRange = tableText.range(of: "|", range: searchStart..<tableText.endIndex) {
                let utf16Offset = tableText.utf16.distance(from: tableText.startIndex, to: pipeRange.lowerBound)
                let absoluteLocation = tableRange.location + utf16Offset
                styledRanges.append(
                    (
                        NSRange(location: absoluteLocation, length: 1),
                        [
                            .font: hiddenFont,
                            .foregroundColor: NSColor.clear,
                        ]
                    ))
                searchStart = pipeRange.upperBound
            }

            // Hide the separator row (the `|---|---|---|` line between
            // Table.Head and the first Table.Row in Table.Body). swift-
            // markdown doesn't expose this row as a node, but its source
            // range sits between Head.upperBound and Body.first.lowerBound.
            if let head = table.head.range,
                let firstBodyRow = table.body.children.compactMap({ ($0 as? Table.Row)?.range }).first
            {
                let separatorStartLine = head.upperBound.line + 1
                let separatorEndLine = firstBodyRow.lowerBound.line - 1
                if separatorStartLine <= separatorEndLine,
                    let startOffset = lineIndex.utf16Offset(line: separatorStartLine, column: 1),
                    let endOffset = lineIndex.utf16Offset(line: separatorEndLine + 1, column: 1)
                {
                    let clampedEnd = min(endOffset, nsText.length)
                    if clampedEnd > startOffset {
                        let sepRange = NSRange(location: startOffset, length: clampedEnd - startOffset)
                        styledRanges.append(
                            (
                                sepRange,
                                [
                                    .font: hiddenFont,
                                    .foregroundColor: NSColor.clear,
                                ]
                            ))
                    }
                }
            }

            for child in table.children {
                visit(child)
            }
        }

        mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
            // Pommora: ThematicBreak visual styling (font/color/paragraphStyle)
            // is owned entirely by the caret-awareness service in
            // NativeTextViewCoordinator (see syncHRVisibility). The service
            // applies all three attributes ONLY when the caret has left the HR
            // paragraph, so the visual "commit" (dashes hide + line appears +
            // 16/16 paragraphSpacing appears) happens on caret-leave (typically
            // Enter) — not at parser-detection time. Emitting any HR-specific
            // attribute here would fire on every keystroke (since the parser
            // detects `---` immediately on the 3rd dash), breaking the
            // "Enter is the trigger" UX promise.
            //
            // ThematicBreak has no children worth walking; nothing to do.
            _ = thematicBreak
        }
    }
}

// MARK: - SourceRange → NSRange conversion

/// Apple swift-markdown reports `SourceRange` as (line: 1-based, column: 1-based).
/// Converts those to NSRange (utf16 offset) for NSAttributedString consumption.
/// Builds a per-parse line-offset index so multi-line ranges convert in O(log n).
enum SourceRangeConverter {
    static func nsRange(from sourceRange: SourceRange?, in nsText: NSString, lineIndex: LineOffsetIndex) -> NSRange? {
        guard let sourceRange else { return nil }
        let startLine = sourceRange.lowerBound.line
        let startCol = sourceRange.lowerBound.column
        let endLine = sourceRange.upperBound.line
        let endCol = sourceRange.upperBound.column

        guard let startOffset = lineIndex.utf16Offset(line: startLine, column: startCol) else { return nil }
        guard let endOffset = lineIndex.utf16Offset(line: endLine, column: endCol) else { return nil }

        let clampedEnd = min(endOffset, nsText.length)
        let clampedStart = min(startOffset, clampedEnd)
        return NSRange(location: clampedStart, length: clampedEnd - clampedStart)
    }
}

/// Per-parse line-offset cache. `lineStarts[i]` is the utf16 offset of the
/// start of line `i+1` (lines are 1-based in swift-markdown's SourceRange).
///
/// Also holds each line's text content so `utf16Offset(line:column:)` can
/// convert cmark-gfm's UTF-8 byte-offset columns into NSString-compatible
/// UTF-16 code-unit offsets. ASCII content collapses to a direct addition;
/// multi-byte content (emoji, accented chars, non-Latin scripts) requires
/// the per-codepoint walk.
struct LineOffsetIndex {
    private let lineStarts: [Int]
    private let lineTexts: [String]
    private let totalLength: Int

    init(text: String) {
        let nsText = text as NSString
        var starts: [Int] = [0]
        var texts: [String] = []
        starts.reserveCapacity(64)
        texts.reserveCapacity(64)
        var lineStartIdx = 0
        var i = 0
        let length = nsText.length
        while i < length {
            let ch = nsText.character(at: i)
            // \n, or \r not followed by \n, or \r\n — each starts a new line.
            if ch == 0x0A {  // \n
                let lineRange = NSRange(location: lineStartIdx, length: i - lineStartIdx)
                texts.append(nsText.substring(with: lineRange))
                starts.append(i + 1)
                lineStartIdx = i + 1
                i += 1
            } else if ch == 0x0D {  // \r
                let lineRange = NSRange(location: lineStartIdx, length: i - lineStartIdx)
                texts.append(nsText.substring(with: lineRange))
                if i + 1 < length, nsText.character(at: i + 1) == 0x0A {
                    starts.append(i + 2)
                    lineStartIdx = i + 2
                    i += 2
                } else {
                    starts.append(i + 1)
                    lineStartIdx = i + 1
                    i += 1
                }
            } else {
                i += 1
            }
        }
        // Capture the final line (if the text doesn't end in a newline).
        if lineStartIdx <= length {
            let lineRange = NSRange(location: lineStartIdx, length: length - lineStartIdx)
            texts.append(nsText.substring(with: lineRange))
        }
        self.lineStarts = starts
        self.lineTexts = texts
        self.totalLength = length
    }

    /// Convert (line: 1-based, column: 1-based UTF-8 byte offset) → utf16
    /// code-unit offset from the start of the text. cmark-gfm / swift-markdown
    /// report `column` as UTF-8 bytes per the CommonMark spec; this converts
    /// to NSString-compatible UTF-16 code units for NSAttributedString range
    /// consumption. Returns nil for out-of-range line numbers.
    func utf16Offset(line: Int, column: Int) -> Int? {
        let lineIdx = line - 1
        guard lineIdx >= 0, lineIdx < lineStarts.count else {
            // Past last line: clamp to end of text.
            if lineIdx == lineStarts.count { return totalLength }
            return nil
        }
        let lineStart = lineStarts[lineIdx]
        let targetByteOffset = column - 1
        guard targetByteOffset > 0 else { return lineStart }

        // Walk the line's text scalar-by-scalar, tracking UTF-8 bytes
        // consumed and UTF-16 code units accumulated. For ASCII this is
        // a no-op (1 byte = 1 code unit); for multi-byte content the two
        // counts diverge.
        guard lineIdx < lineTexts.count else {
            return min(lineStart + targetByteOffset, totalLength)
        }
        let lineText = lineTexts[lineIdx]
        var bytesConsumed = 0
        var utf16Consumed = 0
        for scalar in lineText.unicodeScalars {
            if bytesConsumed >= targetByteOffset { break }
            bytesConsumed += scalar.utf8.count
            utf16Consumed += scalar.utf16.count
        }
        return min(lineStart + utf16Consumed, totalLength)
    }
}
