import Foundation
import Testing
@testable import MarkdownPM

/// Pins the DETECTION heading rule (`MarkdownDetection.isHeadingLine`):
/// a Stage-1 regex prefilter `^#{1,6}([ \t]|$)` followed by a Stage-2
/// `Markdown.Document(parsing:)` AST confirm (MarkdownDetection.swift:155,160).
/// This DIVERGES from the styler's `headingRegex` (`#{1,6} +`, space-only).
/// Phase 4 unifies the two to the CommonMark space/tab/EOL rule (divergence
/// D-HEAD-1); this characterizes the detection path's current acceptance set.
@Suite("HeadingDetectorCorpus")
struct HeadingDetectorCorpusTests {

    private func isHeading(_ line: String) -> Bool {
        MarkdownDetection.isHeadingLine(line, isInsideCodeBlock: false)
    }

    @Test("`## Foo` (space) is a heading on the detection path")
    func spaceIsHeading() { #expect(isHeading("## Foo")) }

    @Test("`##\\tFoo` (tab) IS a heading on the detection path (diverges from styler)")
    func tabIsHeading_currentBehavior() {
        // VERIFIED against source + Apple AST: Stage-1 `[ \t]` admits the tab,
        // and the Stage-2 `Document(parsing:)` confirm ALSO yields a Heading
        // node (swift-markdown 0.8.0 accepts a tab after the `#` run). The
        // styler's ` +` does NOT — that is the real D-HEAD-1 divergence Phase 4
        // reconciles to one rule.
        #expect(isHeading("##\tFoo"))
    }

    @Test("Bare `###` (EOL) IS a heading on the detection path")
    func bareIsHeading_currentBehavior() {
        // `^#{1,6}([ \t]|$)` accepts a hash run terminated by end-of-line.
        #expect(isHeading("###"))
    }

    @Test("`#Foo` (no space) is NOT a heading")
    func noSpaceNotHeading() { #expect(!isHeading("#Foo")) }

    @Test("7 hashes `####### x` is NOT a heading (max 6)")
    func sevenHashesNotHeading() { #expect(!isHeading("####### x")) }

    @Test("Heading inside a code block is NOT a heading (stage-0 guard)")
    func insideCodeBlockNotHeading() {
        #expect(!MarkdownDetection.isHeadingLine("## Foo", isInsideCodeBlock: true))
    }
}
