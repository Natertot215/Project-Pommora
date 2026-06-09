import Foundation
import Testing
@testable import MarkdownPM

/// Characterizes the `{{ }}` chip-link tokenizing path — the parallel of the
/// `[[ ]]` wikiLink path. The tokenizer must emit a distinct `.chipLink` token
/// (never cross-matching `.wikiLink`) and tolerate a `|` alias the same way the
/// wikiLink regex does.
@Suite("ChipLinkTokenizerTests")
struct ChipLinkTokenizerTests {

    private func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer.parseTokens(in: text)
    }

    @Test("{{Foo}} → exactly one .chipLink token with content \"Foo\"")
    func singleChipLink() {
        let t = tokens("{{Foo}}").filter { $0.kind == .chipLink }
        #expect(t.count == 1)
        #expect(("{{Foo}}" as NSString).substring(with: t[0].contentRange) == "Foo")
    }

    @Test("{{a}} {{b}} → two .chipLink tokens")
    func twoChipLinks() {
        let t = tokens("{{a}} {{b}}").filter { $0.kind == .chipLink }
        #expect(t.count == 2)
    }

    @Test("[[Page]] is a wikiLink, NOT a chipLink (the two kinds don't cross-match)")
    func wikiLinkIsNotChipLink() {
        let t = tokens("[[Page]]")
        #expect(t.contains { $0.kind == .wikiLink })
        #expect(!t.contains { $0.kind == .chipLink })
    }

    @Test("{{a|b}} → one .chipLink token with content \"a\" (pipe tolerated, like wikiLink)")
    func pipeAliasTolerated() {
        let t = tokens("{{a|b}}").filter { $0.kind == .chipLink }
        #expect(t.count == 1)
        #expect(("{{a|b}}" as NSString).substring(with: t[0].contentRange) == "a")
    }
}
