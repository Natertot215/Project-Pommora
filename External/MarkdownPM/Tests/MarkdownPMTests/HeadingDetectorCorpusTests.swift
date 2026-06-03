import Foundation
import Testing
@testable import MarkdownPM

/// Pins the DETECTION heading rule (`MarkdownDetection.isHeadingLine`):
/// a Stage-1 regex prefilter `^#{1,6}([ \t]|$)` followed by a Stage-2
/// `Markdown.Document(parsing:)` AST confirm (MarkdownDetection.swift:155,160).
/// As of Phase 4.3 the styler's `headingRegex` was unified to this same
/// CommonMark space/tab/EOL rule (divergence D-HEAD-1 LANDED), so the two paths
/// no longer diverge — the cross-path agreement is pinned by
/// `TokenizerCorpusTests.headingDetectorsUnified`. This suite characterizes the
/// detection path's acceptance set, which is now the single shared rule.
@Suite("HeadingDetectorCorpus")
struct HeadingDetectorCorpusTests {

    private func isHeading(_ line: String) -> Bool {
        MarkdownDetection.isHeadingLine(line, isInsideCodeBlock: false)
    }

    @Test("`## Foo` (space) is a heading on the detection path")
    func spaceIsHeading() { #expect(isHeading("## Foo")) }

    @Test("`##\\tFoo` (tab) IS a heading on the detection path (now shared with styler)")
    func tabIsHeading() {
        // VERIFIED against source + Apple AST: Stage-1 `[ \t]` admits the tab,
        // and the Stage-2 `Document(parsing:)` confirm ALSO yields a Heading
        // node (swift-markdown 0.8.0 accepts a tab after the `#` run). Post
        // D-HEAD-1 the styler's `headingRegex` accepts this too — see
        // `TokenizerCorpusTests.headingTabAfterHashIsNowToken`.
        #expect(isHeading("##\tFoo"))
    }

    @Test("Bare `###` (EOL) IS a heading on the detection path (now shared with styler)")
    func bareIsHeading() {
        // `^#{1,6}([ \t]|$)` accepts a hash run terminated by end-of-line. Post
        // D-HEAD-1 the styler agrees — see
        // `TokenizerCorpusTests.headingNoSpaceIsNowToken`.
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
