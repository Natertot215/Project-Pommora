import Foundation
import Markdown
import Testing
@testable import MarkdownPM

/// Characterizes `MarkdownTokenizer.appleEmphasisTokens` — the AST-derived
/// emphasis helper (Phase 4.1, unwired). Expected NSRange values were probed
/// against swift-markdown 0.8.0; the SOURCE wins on any disagreement (pin to
/// observed + report the surprise).
@Suite("AppleEmphasisTokens")
struct AppleEmphasisTokensTests {

    private func tokens(_ text: String) -> [MarkdownToken] {
        let doc = Document(parsing: text)
        let ns = text as NSString
        let idx = LineOffsetIndex(text: text)
        return MarkdownTokenizer.appleEmphasisTokens(in: doc, nsText: ns, lineIndex: idx)
    }

    @Test("*a* → one italic, delimiter-inclusive (0,3)")
    func asteriskItalic() {
        let t = tokens("*a*")
        #expect(t.count == 1)
        #expect(t[0].kind == .italic)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 3)))
        #expect(NSEqualRanges(t[0].contentRange, NSRange(location: 1, length: 1)))
        #expect(t[0].markerRanges.count == 2)
        #expect(NSEqualRanges(t[0].markerRanges[0], NSRange(location: 0, length: 1)))
        #expect(NSEqualRanges(t[0].markerRanges[1], NSRange(location: 2, length: 1)))
    }

    @Test("**b** → one bold (0,5)")
    func asteriskBold() {
        let t = tokens("**b**")
        #expect(t.count == 1)
        #expect(t[0].kind == .bold)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 5)))
        #expect(NSEqualRanges(t[0].contentRange, NSRange(location: 2, length: 1)))
        #expect(NSEqualRanges(t[0].markerRanges[0], NSRange(location: 0, length: 2)))
        #expect(NSEqualRanges(t[0].markerRanges[1], NSRange(location: 3, length: 2)))
    }

    @Test("***c*** → one boldItalic — the identical-range collapse (0,7)")
    func asteriskBoldItalicCollapse() {
        let t = tokens("***c***")
        #expect(t.count == 1)
        #expect(t[0].kind == .boldItalic)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 7)))
        #expect(NSEqualRanges(t[0].contentRange, NSRange(location: 3, length: 1)))
        #expect(NSEqualRanges(t[0].markerRanges[0], NSRange(location: 0, length: 3)))
        #expect(NSEqualRanges(t[0].markerRanges[1], NSRange(location: 4, length: 3)))
    }

    @Test("_a_ → underscore emphasizes, one italic (0,3)")
    func underscoreItalic() {
        let t = tokens("_a_")
        #expect(t.count == 1)
        #expect(t[0].kind == .italic)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 3)))
    }

    @Test("__b__ → one bold (0,5)")
    func underscoreBold() {
        let t = tokens("__b__")
        #expect(t.count == 1)
        #expect(t[0].kind == .bold)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 5)))
    }

    @Test("a*b*c → intra-word asterisk allowed, italic (1,3)")
    func intraWordAsterisk() {
        let t = tokens("a*b*c")
        #expect(t.count == 1)
        #expect(t[0].kind == .italic)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 1, length: 3)))
        #expect(NSEqualRanges(t[0].contentRange, NSRange(location: 2, length: 1)))
    }

    @Test("a_b_c → intra-word underscore suppressed, zero tokens")
    func intraWordUnderscore() {
        #expect(tokens("a_b_c").isEmpty)
    }

    @Test("snake_case_word → zero tokens")
    func snakeCase() {
        #expect(tokens("snake_case_word").isEmpty)
    }

    @Test("`a *b* c` → emphasis inside inline code suppressed, zero tokens")
    func insideInlineCode() {
        #expect(tokens("`a *b* c`").isEmpty)
    }

    @Test("*foo\\nbar* → one italic spanning the SoftBreak (0,9)")
    func crossLine() {
        let t = tokens("*foo\nbar*")
        #expect(t.count == 1)
        #expect(t[0].kind == .italic)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 9)))
    }

    @Test("**a *b* c** → genuine sub-span: bold over Strong AND italic over inner *b* (NOT collapsed)")
    func genuineSubSpanNoCollapse() {
        let t = tokens("**a *b* c**")
        let bolds = t.filter { $0.kind == .bold }
        let italics = t.filter { $0.kind == .italic }
        #expect(bolds.count == 1)
        #expect(italics.count == 1)
        // Strong spans the whole `**a *b* c**` (0,11); content is the inner 7 chars.
        #expect(NSEqualRanges(bolds[0].range, NSRange(location: 0, length: 11)))
        #expect(NSEqualRanges(bolds[0].contentRange, NSRange(location: 2, length: 7)))
        // Inner Emphasis spans `*b*` at (4,3); content `b` at (5,1).
        #expect(NSEqualRanges(italics[0].range, NSRange(location: 4, length: 3)))
        #expect(NSEqualRanges(italics[0].contentRange, NSRange(location: 5, length: 1)))
    }

    @Test("**foo*bar**baz* → rule-of-3: ONE bold (0,11), no italic (divergence D-EMPH-3)")
    func ruleOfThree() {
        let t = tokens("**foo*bar**baz*")
        #expect(t.count == 1)
        #expect(t[0].kind == .bold)
        #expect(NSEqualRanges(t[0].range, NSRange(location: 0, length: 11)))
    }
}
