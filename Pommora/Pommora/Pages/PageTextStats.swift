import Foundation
import MarkdownEngine

/// Document statistics for the Page stats footer.
///
/// - `lines` counts raw source lines (standard Markdown lines — a `# Heading`
///   plus a blank line plus a paragraph is three lines).
/// - `words` / `characters` count *rendered prose*: Markdown syntax is stripped
///   via `MarkdownPlainText` before counting, so `## **Bold**` contributes one
///   word ("Bold"), not the markers.
struct PageTextStats: Equatable {
    let lines: Int
    let words: Int
    let characters: Int

    static let empty = PageTextStats(lines: 0, words: 0, characters: 0)

    init(lines: Int, words: Int, characters: Int) {
        self.lines = lines
        self.words = words
        self.characters = characters
    }

    init(body: String) {
        guard !body.isEmpty else {
            self = .empty
            return
        }

        // Raw source lines. A single trailing newline is the line terminator,
        // not the start of a phantom empty line, so strip one before splitting.
        let withoutTrailingNewline = body.hasSuffix("\n") ? String(body.dropLast()) : body
        lines = withoutTrailingNewline.components(separatedBy: "\n").count

        // Rendered prose for word / character counts.
        let prose = MarkdownPlainText.extract(from: body)
        // Count strictly-visible characters: exclude the structural `\n`s the
        // extractor inserts between blocks — they're separators, not characters
        // a reader sees. (Word counting below still runs over the separated
        // prose so words don't fuse across block boundaries.)
        characters = prose.filter { !$0.isNewline }.count

        var wordCount = 0
        prose.enumerateSubstrings(in: prose.startIndex..., options: .byWords) { _, _, _, _ in
            wordCount += 1
        }
        words = wordCount
    }
}
