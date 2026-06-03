import Foundation

/// A deterministic large Markdown document for the Phase-3 MANUAL Instruments
/// capture only — it makes the parse cost observable in a trace. NOT used by
/// any automated parse-count assertion (parse count is size-independent).
/// ~400 paragraphs mixing headings, prose, lists, checkboxes, code fences,
/// blockquotes, wikilinks, and math so the parse cost is representative, not a
/// degenerate single-construct stream.
enum LargeDocumentFixture {
    static let body: String = {
        var s = ""
        for i in 0..<100 {
            s += "## Section \(i)\n"
            s += "Some prose with *italic* and **bold** and `code` and a [[Note \(i)]] link.\n"
            s += "- bullet one\n- [ ] task \(i)\n- [x] done \(i)\n"
            s += "> a quoted line for section \(i)\n"
            s += "```swift\nlet x = \(i)\n```\n"
            s += "Inline math $x_\(i)+y$ and a price of $\(i),000 here.\n\n"
        }
        return s
    }()
}
