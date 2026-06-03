import Foundation
import Testing
@testable import MarkdownPM

/// Characterizes `MarkdownTokenizer.parseTokens(in:)` — the tokenizer that owns
/// emphasis (Apple-AST-derived as of Phase 4.2), inline code, links, headings
/// (styler path), wikilinks, image embeds, and the $…$ math/currency heuristic.
/// The emphasis assertions pin the NEW AST behavior (D-EMPH-1/2/3/4, landed
/// Phase 4.2); the rest pin current regex behavior.
@Suite("TokenizerCorpus")
struct TokenizerCorpusTests {

    // Helper: kinds present, in append order (emphasis first, then embeds,
    // wikilinks, links, headings, code, latex — see parseTokens ordering).
    private func kinds(_ text: String) -> [MarkdownTokenKind] {
        MarkdownTokenizer.parseTokens(in: text).map(\.kind)
    }
    private func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer.parseTokens(in: text)
    }

    // MARK: - Emphasis: Apple-AST-derived (PINNED — divergences D-EMPH-1/2/3/4)

    @Test("Single asterisk pair is italic")
    func italic() {
        let t = tokens("a *b* c")
        let em = t.filter { $0.kind == .italic }
        #expect(em.count == 1)
        // `*b*` starts at utf16 index 2, length 3.
        #expect(em[0].range == NSRange(location: 2, length: 3))
    }

    @Test("Double asterisk pair is bold")
    func bold() {
        let em = tokens("**b**").filter { $0.kind == .bold }
        #expect(em.count == 1)
        #expect(em[0].range == NSRange(location: 0, length: 5))
    }

    @Test("Triple asterisk pair is boldItalic")
    func boldItalic() {
        let em = tokens("***b***").filter { $0.kind == .boldItalic }
        #expect(em.count == 1)
        #expect(em[0].range == NSRange(location: 0, length: 7))
    }

    @Test("Underscore IS emphasis: _b_ italic, __c__ bold (D-EMPH-1, AST)")
    func underscoreIsEmphasis() {
        // D-EMPH-1: the AST adopts CommonMark/Obsidian underscore emphasis.
        // `_b_` → italic (0,3); `__c__` → bold (4,5).
        let em = tokens("_b_ __c__").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.count == 2)
        let italics = em.filter { $0.kind == .italic }
        let bolds = em.filter { $0.kind == .bold }
        #expect(italics.count == 1)
        #expect(italics[0].range == NSRange(location: 0, length: 3))
        #expect(bolds.count == 1)
        #expect(bolds[0].range == NSRange(location: 4, length: 5))
    }

    @Test("Rule-of-3: **foo*bar**baz* → ONE bold (0,11), no italic (D-EMPH-3, AST)")
    func ruleOfThree_a() {
        // D-EMPH-3: Apple's AST emits ONE clean CommonMark node, not the legacy
        // pair of overlapping runs. `**foo*bar**baz*` → a single Strong over
        // (0,11); the trailing `*baz*` is not a closed emphasis (probe-verified
        // 0.8.0). `styleEmphasis` reads only kind+contentRange, so render stays
        // correct.
        let em = tokens("**foo*bar**baz*").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.count == 1)
        #expect(em[0].kind == .bold)
        #expect(em[0].range == NSRange(location: 0, length: 11))
    }

    @Test("Rule-of-3: *foo**bar*baz** → ONE italic (0,10), no bold (D-EMPH-3, AST)")
    func ruleOfThree_b() {
        // D-EMPH-3: Apple emits a single Emphasis over (0,10); the trailing
        // `**baz**` is not a closed strong (probe-verified 0.8.0). No overlap.
        let em = tokens("*foo**bar*baz**").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.count == 1)
        #expect(em[0].kind == .italic)
        #expect(em[0].range == NSRange(location: 0, length: 10))
    }

    @Test("Intra-word a*b*c emphasizes the inner asterisk pair")
    func intraWord() {
        let em = tokens("a*b*c").filter { $0.kind == .italic }
        #expect(em.count == 1)
        #expect(em[0].range == NSRange(location: 1, length: 3))
    }

    @Test("Intra-word underscore is suppressed: a_b_c → 0 tokens (D4.2-a, AST)")
    func intraWordUnderscore() {
        // D4.2-a: CommonMark/Apple disallow intra-word underscore emphasis.
        let em = tokens("a_b_c").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.isEmpty)
    }

    @Test("snake_case_word → 0 emphasis tokens (D4.2-a, AST)")
    func snakeCaseNoEmphasis() {
        let em = tokens("snake_case_word").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.isEmpty)
    }

    @Test("Cross-line *foo\\nbar* emphasizes across the SoftBreak (D-EMPH-4, AST)")
    func crossLine() {
        // D-EMPH-4: Apple emphasizes across the SoftBreak as one node,
        // NSRange (0,9) — CommonMark-correct, matches Obsidian (the legacy
        // per-line stack rejected this).
        let em = tokens("*foo\nbar*").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.count == 1)
        #expect(em[0].kind == .italic)
        #expect(em[0].range == NSRange(location: 0, length: 9))
    }

    @Test("Punctuation-flanking *(*  edge cases produce no spurious emphasis")
    func punctuationFlanking() {
        let em = tokens("a * b * c").filter { $0.kind == .italic }
        // Spaces inside the asterisks defeat flanking; no italic token.
        #expect(em.isEmpty)
    }

    @Test("Emphasis inside inline code IS suppressed (D-EMPH-2, AST)")
    func emphasisInsideInlineCodeSuppressed() {
        // D-EMPH-2: Apple does not emit Emphasis/Strong inside InlineCode, so
        // `*x*` inside backticks yields no emphasis token — code suppression is
        // free (the legacy regex emission emitted one italic here).
        let em = tokens("`*x*`").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.isEmpty)
    }

    // MARK: - Inline code (multi-backtick + content range)

    @Test("Single-backtick inline code: marker ranges are the backticks")
    func inlineCodeSingle() {
        let t = tokens("a `code` b").filter { $0.kind == .inlineCode }
        #expect(t.count == 1)
        #expect(t[0].range == NSRange(location: 2, length: 6))   // `code`
        #expect(t[0].contentRange == NSRange(location: 3, length: 4)) // code
        #expect(t[0].markerRanges.count == 2)
    }

    @Test("Multi-backtick run: the inlineCodeRegex only matches single backticks")
    func inlineCodeMultiBacktick_currentBehavior() {
        // inlineCodeRegex = `([^`\n]+)` — a single backtick on each side.
        // ``a`b`` is therefore matched as `b` between the inner ticks, not
        // the whole double-backtick span. Pin whatever it actually does.
        let t = tokens("``a`b``").filter { $0.kind == .inlineCode }
        // Record the count the regex produces (do not assume CommonMark here).
        #expect(t.count == 1)
    }

    // MARK: - Links (take the destination)

    @Test("Markdown link [text](url): contentRange is the text, markers bracket+paren")
    func markdownLink() {
        let t = tokens("see [text](https://x.io) end").filter { $0.kind == .link }
        #expect(t.count == 1)
        #expect((("see [text](https://x.io) end" as NSString)
            .substring(with: t[0].contentRange)) == "text")
        #expect(t[0].markerRanges.count == 4) // [ ] ( )
    }

    // MARK: - Headings (STYLER path — requires a space; PINNED D-HEAD-1)

    @Test("Styler heading regex: `## Foo` is a heading token")
    func headingWithSpace() {
        let t = tokens("## Foo").filter { $0.kind == .heading }
        #expect(t.count == 1)
    }

    @Test("Styler heading regex: bare `##` (no space) is NOT a token")
    func headingNoSpace_currentBehavior() {
        // headingRegex = ^\s*(#{1,6}) +(.*)$  — REQUIRES at least one space.
        let t = tokens("##").filter { $0.kind == .heading }
        #expect(t.isEmpty)
    }

    @Test("Styler heading regex: tab-after-hash `##\\tFoo` is NOT a token")
    func headingTabAfterHash_currentBehavior() {
        // VERIFIED against source: styler headingRegex `^\s*(#{1,6}) +(.*)$`
        // (MarkdownTokenizer.swift:23-24) uses ` +` (U+0020 only, no tabs), so
        // `##\tFoo` does NOT tokenize as a heading on the styler path. The
        // DETECTION path DOES accept it (verified: isHeadingLine("##\tFoo")
        // == true) — that is the real D-HEAD-1 divergence Phase 4 reconciles.
        let t = tokens("##\tFoo").filter { $0.kind == .heading }
        #expect(t.isEmpty)
    }

    // MARK: - Wikilinks + image embeds (STAY regex through the rebuild)

    @Test("Plain wikilink [[Title]] tokenizes; markers are the [[ and ]]")
    func wikilinkPlain() {
        let t = tokens("a [[Title]] b").filter { $0.kind == .wikiLink }
        #expect(t.count == 1)
        #expect((("a [[Title]] b" as NSString)
            .substring(with: t[0].contentRange)) == "Title")
    }

    @Test("Path-qualified inbound [[folder/Title]] reads as one wikilink")
    func wikilinkPathQualified() {
        let t = tokens("[[folder/Title]]").filter { $0.kind == .wikiLink }
        #expect(t.count == 1)
        #expect((("[[folder/Title]]" as NSString)
            .substring(with: t[0].contentRange)) == "folder/Title")
    }

    @Test(".md-suffixed inbound [[Title.md]] reads as one wikilink")
    func wikilinkMdSuffixed() {
        let t = tokens("[[Title.md]]").filter { $0.kind == .wikiLink }
        #expect(t.count == 1)
    }

    @Test("Image embed ![[Img]] is imageEmbed, NOT wikiLink")
    func imageEmbed() {
        let t = tokens("![[Img]]")
        #expect(t.contains { $0.kind == .imageEmbed })
        #expect(!t.contains { $0.kind == .wikiLink })
    }

    // MARK: - $…$ math vs currency heuristic (thresholds 120/40/6 — PIN VERBATIM)

    @Test("$5 is currency (money), NOT inline LaTeX")
    func dollarFiveIsMoney() {
        let t = tokens("costs $5 today").filter { $0.kind == .inlineLatex }
        #expect(t.isEmpty)
    }

    @Test("$1,234.56 is currency, NOT LaTeX")
    func dollarThousandsIsMoney() {
        let t = tokens("$1,234.56").filter { $0.kind == .inlineLatex }
        #expect(t.isEmpty)
    }

    @Test("$x+y$ is inline LaTeX (mathy chars, short)")
    func mathExpression() {
        let t = tokens("$x+y$").filter { $0.kind == .inlineLatex }
        #expect(t.count == 1)
    }

    @Test("$x$ (1-3 letter run, 0 mathy) is treated as math")
    func singleLetterIsMath() {
        let t = tokens("$x$").filter { $0.kind == .inlineLatex }
        #expect(t.count == 1)
    }

    @Test("$abc$ (3-letter run, 0 mathy) is math")
    func threeLetterIsMath() {
        let t = tokens("$abc$").filter { $0.kind == .inlineLatex }
        #expect(t.count == 1)
    }

    @Test("$abcd$ (4-letter run, 0 mathy) is NOT math")
    func fourLetterNotMath() {
        let t = tokens("$abcd$").filter { $0.kind == .inlineLatex }
        #expect(t.isEmpty)
    }

    // Threshold boundary: 1 mathy char tolerates ≤ 6 whitespace tokens.
    @Test("1 mathy char with 6 tokens is math; 7 is not (threshold 6)")
    func oneMathyThreshold() {
        // Build "a a a a a a +" → 7 whitespace-separated tokens, 1 mathy (+).
        let sevenTokens = "$a a a a a a +$"   // tokens.count == 7 → NOT math
        let sixTokens = "$a a a a a +$"       // tokens.count == 6 → math
        #expect(tokens(sevenTokens).filter { $0.kind == .inlineLatex }.isEmpty)
        #expect(tokens(sixTokens).filter { $0.kind == .inlineLatex }.count == 1)
    }
}
