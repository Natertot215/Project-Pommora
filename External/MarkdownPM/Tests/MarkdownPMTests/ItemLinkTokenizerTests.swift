import Foundation
import Testing
@testable import MarkdownPM

/// Characterizes the `{{ }}` item-link tokenizing path — the parallel of the
/// `[[ ]]` wikiLink path. The tokenizer must emit a distinct `.itemLink` token
/// (never cross-matching `.wikiLink`) and tolerate a `|` alias the same way the
/// wikiLink regex does.
@Suite("ItemLinkTokenizerTests")
struct ItemLinkTokenizerTests {

    private func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer.parseTokens(in: text)
    }

    @Test("{{Foo}} → exactly one .itemLink token with content \"Foo\"")
    func singleItemLink() {
        let t = tokens("{{Foo}}").filter { $0.kind == .itemLink }
        #expect(t.count == 1)
        #expect(("{{Foo}}" as NSString).substring(with: t[0].contentRange) == "Foo")
    }

    @Test("{{a}} {{b}} → two .itemLink tokens")
    func twoItemLinks() {
        let t = tokens("{{a}} {{b}}").filter { $0.kind == .itemLink }
        #expect(t.count == 2)
    }

    @Test("[[Page]] is a wikiLink, NOT an itemLink (the two kinds don't cross-match)")
    func wikiLinkIsNotItemLink() {
        let t = tokens("[[Page]]")
        #expect(t.contains { $0.kind == .wikiLink })
        #expect(!t.contains { $0.kind == .itemLink })
    }

    @Test("{{a|b}} → one .itemLink token with content \"a\" (pipe tolerated, like wikiLink)")
    func pipeAliasTolerated() {
        let t = tokens("{{a|b}}").filter { $0.kind == .itemLink }
        #expect(t.count == 1)
        #expect(("{{a|b}}" as NSString).substring(with: t[0].contentRange) == "a")
    }
}
