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

    /// Invariant guard: every `*`/`_` delimiter that lands inside SOME token's
    /// `contentRange` (and would therefore receive an emphasis trait via
    /// `styleEmphasis`) MUST also be covered by SOME token's `markerRange` (and
    /// therefore be HIDDEN by `shrinkInactiveMarkers`). A delimiter that is
    /// styled-but-not-hidden is the stray-`*` regression. A delimiter inside an
    /// OUTER token's content is fine when it is the inner token's marker — it
    /// gets hidden by that inner token. This is the real "no VISIBLE delimiter
    /// receives an emphasis trait" invariant.
    private func assertNoStrayStyledDelimiter(
        _ text: String, _ sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) {
        let ns = text as NSString
        let ts = tokens(text)
        var styled = Set<Int>()
        var hidden = Set<Int>()
        for t in ts {
            for i in t.contentRange.location..<NSMaxRange(t.contentRange) { styled.insert(i) }
            for m in t.markerRanges {
                for i in m.location..<NSMaxRange(m) { hidden.insert(i) }
            }
        }
        for i in 0..<ns.length {
            let c = ns.substring(with: NSRange(location: i, length: 1))
            guard c == "*" || c == "_" else { continue }
            if styled.contains(i) {
                #expect(
                    hidden.contains(i),
                    "delimiter '\(c)' at \(i) is STYLED but not HIDDEN (stray styled delimiter)",
                    sourceLocation: sourceLocation)
            }
        }
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

    // MARK: Nested-adjacent + unbalanced delimiters (Phase-4 review)
    //
    // Regression guard for the width-subtraction bug: when an inner Strong/
    // Emphasis ABUTS the outer emphasis's delimiter run, Apple reports the
    // inner node's `.range` starting ON a delimiter char owned by the OUTER
    // node. Reconstructing markers from the inner node's absolute boundaries
    // trapped a literal `*`/`_` in the bold `contentRange` (a stray styled
    // delimiter visible mid-text). The fix anchors markers on the content's
    // child spans; expected ranges below match the retired stack parser
    // byte-for-byte on asterisk input (its content/marker geometry was correct
    // for these clean CommonMark cases — they are NOT logged divergences).

    @Test("***bold** then italic* → bold content 'bold' (3,4), markers (1,2)/(7,2) — NOT '*bold'")
    func nestedAdjacentLeadingBold() {
        let t = tokens("***bold** then italic*")
        let bold = t.first { $0.kind == .bold }
        let italic = t.first { $0.kind == .italic }
        #expect(bold != nil)
        #expect(italic != nil)
        #expect(NSEqualRanges(bold!.range, NSRange(location: 1, length: 8)))
        #expect(NSEqualRanges(bold!.contentRange, NSRange(location: 3, length: 4)))  // 'bold'
        #expect(NSEqualRanges(bold!.markerRanges[0], NSRange(location: 1, length: 2)))
        #expect(NSEqualRanges(bold!.markerRanges[1], NSRange(location: 7, length: 2)))
        // Outer italic keeps the leading/trailing `*` at index 0 and 21.
        #expect(NSEqualRanges(italic!.markerRanges[0], NSRange(location: 0, length: 1)))
        #expect(NSEqualRanges(italic!.markerRanges[1], NSRange(location: 21, length: 1)))
        assertNoStrayStyledDelimiter("***bold** then italic*")
    }

    @Test("*italic then **bold*** → bold content 'bold' (15,4), markers (13,2)/(19,2) — NOT 'bold*'")
    func nestedAdjacentTrailingBold() {
        let t = tokens("*italic then **bold***")
        let bold = t.first { $0.kind == .bold }
        #expect(bold != nil)
        #expect(NSEqualRanges(bold!.range, NSRange(location: 13, length: 8)))
        #expect(NSEqualRanges(bold!.contentRange, NSRange(location: 15, length: 4)))  // 'bold'
        #expect(NSEqualRanges(bold!.markerRanges[0], NSRange(location: 13, length: 2)))
        #expect(NSEqualRanges(bold!.markerRanges[1], NSRange(location: 19, length: 2)))
        assertNoStrayStyledDelimiter("*italic then **bold***")
    }

    @Test("***Warning:** read this carefully* → bold content 'Warning:' (3,8), markers (1,2)/(11,2)")
    func nestedAdjacentWarning() {
        let t = tokens("***Warning:** read this carefully*")
        let bold = t.first { $0.kind == .bold }
        #expect(bold != nil)
        #expect(NSEqualRanges(bold!.contentRange, NSRange(location: 3, length: 8)))  // 'Warning:'
        #expect(NSEqualRanges(bold!.markerRanges[0], NSRange(location: 1, length: 2)))
        #expect(NSEqualRanges(bold!.markerRanges[1], NSRange(location: 11, length: 2)))
        assertNoStrayStyledDelimiter("***Warning:** read this carefully*")
    }

    @Test("**a* → unbalanced: italic content 'a' (2,1), markers (1,1)/(3,1) — leading stray * not styled")
    func unbalancedLeading() {
        let t = tokens("**a*")
        let italic = t.first { $0.kind == .italic }
        #expect(italic != nil)
        #expect(NSEqualRanges(italic!.range, NSRange(location: 1, length: 3)))
        #expect(NSEqualRanges(italic!.contentRange, NSRange(location: 2, length: 1)))  // 'a'
        #expect(NSEqualRanges(italic!.markerRanges[0], NSRange(location: 1, length: 1)))
        #expect(NSEqualRanges(italic!.markerRanges[1], NSRange(location: 3, length: 1)))
        assertNoStrayStyledDelimiter("**a*")
    }

    @Test("*a** → unbalanced: italic content 'a' (1,1), markers (0,1)/(2,1) — trailing stray * not styled")
    func unbalancedTrailing() {
        let t = tokens("*a**")
        let italic = t.first { $0.kind == .italic }
        #expect(italic != nil)
        #expect(NSEqualRanges(italic!.range, NSRange(location: 0, length: 3)))
        #expect(NSEqualRanges(italic!.contentRange, NSRange(location: 1, length: 1)))  // 'a'
        #expect(NSEqualRanges(italic!.markerRanges[0], NSRange(location: 0, length: 1)))
        #expect(NSEqualRanges(italic!.markerRanges[1], NSRange(location: 2, length: 1)))
        assertNoStrayStyledDelimiter("*a**")
    }

    @Test("****d**** → same-type identical-range nesting: ONE bold over 'd' (4,1), no double-emit")
    func sameTypeIdenticalRange() {
        let t = tokens("****d****")
        let bolds = t.filter { $0.kind == .bold }
        #expect(bolds.count == 1)  // inner Strong emits; outer descends without re-emitting.
        #expect(NSEqualRanges(bolds[0].contentRange, NSRange(location: 4, length: 1)))  // 'd'
        #expect(NSEqualRanges(bolds[0].markerRanges[0], NSRange(location: 2, length: 2)))
        #expect(NSEqualRanges(bolds[0].markerRanges[1], NSRange(location: 5, length: 2)))
        assertNoStrayStyledDelimiter("****d****")
    }

    @Test("Underscore analogue: ___bold__ then italic_ → bold content 'bold' (3,4), markers __/__")
    func nestedAdjacentUnderscore() {
        let t = tokens("___bold__ then italic_")
        let bold = t.first { $0.kind == .bold }
        #expect(bold != nil)
        #expect(NSEqualRanges(bold!.contentRange, NSRange(location: 3, length: 4)))  // 'bold'
        #expect(NSEqualRanges(bold!.markerRanges[0], NSRange(location: 1, length: 2)))
        #expect(NSEqualRanges(bold!.markerRanges[1], NSRange(location: 7, length: 2)))
        assertNoStrayStyledDelimiter("___bold__ then italic_")
    }
}
