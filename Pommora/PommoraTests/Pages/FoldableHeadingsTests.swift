import Foundation
import MarkdownEngine
import Testing

/// Tests for `MarkdownDetection.foldableHeadings` — the AST walker that pairs
/// each top-level heading with its content NSRange (until the next equal-or-
/// higher heading or document end). The engine's HeadingFolding service
/// (Phase 4) consumes this output; correctness here is the foundation for
/// everything downstream.
@Suite("FoldableHeadings")
struct FoldableHeadingsTests {

    // MARK: - Empty / trivial cases

    @Test("Empty document returns no headings")
    func emptyDocument() {
        #expect(MarkdownDetection.foldableHeadings(in: "").isEmpty)
    }

    @Test("Document with no headings returns no entries")
    func proseOnly() {
        let text = "Just a paragraph.\n\nAnother paragraph.\n"
        #expect(MarkdownDetection.foldableHeadings(in: text).isEmpty)
    }

    // MARK: - Single headings

    @Test("Single H1 at top — content spans rest of document")
    func singleHeadingAtTop() {
        let text = "# Top\nbody one\nbody two\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 1)
        #expect(headings[0].key == "# Top")
        #expect(headings[0].level == 1)
        // Heading line is "# Top\n" → NSRange(0, 6).
        #expect(headings[0].headingRange == NSRange(location: 0, length: 6))
        // Content starts after the heading's newline, runs to end (length 18).
        #expect(headings[0].contentRange.location == 6)
        #expect(headings[0].contentRange.location + headings[0].contentRange.length == (text as NSString).length)
    }

    @Test("Trailing heading with no content has zero-length contentRange")
    func trailingHeadingNoContent() {
        let text = "para\n\n## Trailing\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 1)
        #expect(headings[0].key == "## Trailing")
        #expect(headings[0].contentRange.length == 0)
    }

    @Test("Heading with no trailing newline still keys cleanly")
    func headingWithoutTrailingNewline() {
        // No trailing newline — common for file end.
        let text = "## Endpoint"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 1)
        #expect(headings[0].key == "## Endpoint")
    }

    // MARK: - Multiple headings

    @Test("H1 then H2 — H1 content includes the H2 + its body")
    func h1ContainsH2() {
        let text = "# Top\nintro\n## Sub\nsub body\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 2)
        #expect(headings[0].key == "# Top")
        #expect(headings[1].key == "## Sub")
        // H1's contentRange should cover from after "# Top\n" to end of document.
        // (The next heading at level <= 1 is none, so it runs to docEnd.)
        #expect(headings[0].contentRange.location == 6)  // after "# Top\n"
        #expect(headings[0].contentRange.location + headings[0].contentRange.length == (text as NSString).length)
        // H2's contentRange covers from after "## Sub\n" to end of document.
        #expect(headings[1].contentRange.length == ("sub body\n" as NSString).length)
    }

    @Test("Sibling H2s — first H2 closes when second H2 begins")
    func siblingH2sCloseEachOther() {
        let text = "## A\naa\n## B\nbb\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 2)
        let first = headings[0]
        let second = headings[1]
        // first H2's content ends where second H2 begins.
        #expect(first.contentRange.location + first.contentRange.length == second.headingRange.location)
        // second H2's content runs to document end.
        #expect(second.contentRange.location + second.contentRange.length == (text as NSString).length)
    }

    @Test("H2 > H3 > H2 — H3 content closes at second H2, NOT at any deeper boundary")
    func nestedH3ClosesAtParentSibling() {
        let text = """
            ## First
            a
            ### Inner
            i
            ## Second
            s
            """
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 3)
        #expect(headings[0].key == "## First")
        #expect(headings[1].key == "### Inner")
        #expect(headings[2].key == "## Second")
        // H3 (Inner) content ends at second H2's heading start.
        let inner = headings[1]
        let second = headings[2]
        #expect(inner.contentRange.location + inner.contentRange.length == second.headingRange.location)
    }

    @Test("Equal-or-higher rule — H3 does NOT close an H4 that follows")
    func higherLevelClosesLower() {
        let text = """
            ### Level3
            x
            #### Level4
            y
            ## Level2
            z
            """
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 3)
        // Level4 (H4) sits under Level3 (H3) — closes when Level2 (H2) appears
        // because H2 has level <= H4.
        let level4 = headings[1]
        let level2 = headings[2]
        #expect(level4.contentRange.location + level4.contentRange.length == level2.headingRange.location)
        // Level3 (H3) also closes at Level2 since H2 <= H3.
        let level3 = headings[0]
        #expect(level3.contentRange.location + level3.contentRange.length == level2.headingRange.location)
    }

    // MARK: - Code-block exclusion

    @Test("Heading inside fenced code block is NOT foldable")
    func headingInsideFencedCodeBlock() {
        let text = """
            ## Real heading
            body
            ```
            # Not a heading
            ## Also not
            ```
            after
            """
        let headings = MarkdownDetection.foldableHeadings(in: text)
        // Only the top heading is real; the two `#` lines inside the fenced
        // block parse as code content per CommonMark.
        #expect(headings.count == 1)
        #expect(headings[0].key == "## Real heading")
    }

    // MARK: - CRLF compatibility

    @Test("CRLF line endings — keys strip both \\r and \\n")
    func crlfStripsBothNewlineBytes() {
        let text = "## Foo\r\nbody\r\n## Bar\r\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 2)
        // Neither key should retain a \r tail.
        #expect(headings[0].key == "## Foo")
        #expect(headings[1].key == "## Bar")
    }

    // MARK: - Closing-hash form

    @Test("ATX closing-hash form is preserved in the key")
    func closingHashFormKey() {
        let text = "## Foo ##\nbody\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 1)
        // The raw source line — closing `##` is part of the key, not stripped.
        // Two pages with `## Foo` vs `## Foo ##` deliberately get distinct keys.
        #expect(headings[0].key == "## Foo ##")
    }

    // MARK: - Indempotence + ordering

    @Test("Results are returned in document order")
    func documentOrderPreserved() {
        let text = """
            # A
            ## B
            ### C
            ## D
            # E
            """
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.map { $0.key } == ["# A", "## B", "### C", "## D", "# E"])
    }

    // MARK: - Ordinal disambiguation (Decision 1)

    @Test("Duplicate H2 headings — second occurrence keyed with [2] suffix")
    func duplicateHeadingsOrdinalDisambiguation() {
        let text = "## Notes\nfirst\n## Notes\nsecond\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 2)
        #expect(headings[0].key == "## Notes")
        #expect(headings[1].key == "## Notes [2]")
    }

    @Test("Three duplicates produce [2] and [3] suffixes")
    func threeDuplicates() {
        let text = "## A\n1\n## A\n2\n## A\n3\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 3)
        #expect(headings.map { $0.key } == ["## A", "## A [2]", "## A [3]"])
    }

    @Test("Non-adjacent duplicates still get ordinals")
    func nonAdjacentDuplicates() {
        let text = "## A\n1\n## B\n2\n## A\n3\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 3)
        #expect(headings.map { $0.key } == ["## A", "## B", "## A [2]"])
    }

    @Test("Different-level same-text headings get separate ordinal counters")
    func differentLevelsSameText() {
        // `## A` and `### A` are not duplicates of each other; their level
        // prefixes differ, so each gets its own ordinal sequence.
        let text = "## A\n1\n### A\n2\n## A\n3\n### A\n4\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 4)
        #expect(headings.map { $0.key } == ["## A", "### A", "## A [2]", "### A [2]"])
    }
}
