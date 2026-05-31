//
//  MarkdownPlainText.swift
//  MarkdownEngine
//
//  Rendered-prose extraction: walks a parsed Markdown document and returns its
//  readable text with all syntax stripped (no `#`, `*`, `-`, link URLs). Used
//  by the Page stats footer for word / character counts that reflect what a
//  reader sees, not the raw source.
//

import Foundation
import Markdown

public enum MarkdownPlainText {
    /// Returns `markdown` with its syntax removed: heading / emphasis / list
    /// markers and link URLs are dropped; link + heading + emphasis *text* is
    /// kept. Block elements are newline-separated so words don't merge across
    /// paragraphs.
    public static func extract(from markdown: String) -> String {
        var walker = PlainTextWalker()
        walker.visit(Document(parsing: markdown))
        return walker.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PlainTextWalker: MarkupWalker {
    var text = ""

    mutating func visitText(_ text: Markdown.Text) { self.text += text.string }
    mutating func visitInlineCode(_ inlineCode: InlineCode) { self.text += inlineCode.code }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) { self.text += codeBlock.code }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { self.text += " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { self.text += " " }

    mutating func defaultVisit(_ markup: Markup) {
        descendInto(markup)
        // Separate block elements so the last word of one block doesn't fuse
        // with the first word of the next during word counting.
        if markup is BlockMarkup { text += "\n" }
    }
}
