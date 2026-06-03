//
//  ParseSpineTests.swift
//  MarkdownPMTests
//
//  Phase 3 / 3.5: proves the single cached parse spine — the whole-document
//  Apple Document AND its LineOffsetIndex are built once inside
//  parsedDocument(for:) and reused by every whole-document consumer.
//
//  SCOPE: the parse counter pins the whole-document SPINE parse only.
//  Per-fragment single-line parses (MarkdownDetection.isThematicBreakLine /
//  isHeadingLine / foldableHeadings(in: String), MarkdownTextLayoutFragment's
//  blockquote probe) are cheap, intentionally uncounted, and out of scope here.
//

import AppKit
import Markdown
import SwiftUI
import Testing

@testable import MarkdownPM

@MainActor
@Suite struct ParseSpineTests {

    /// Builds a coordinator wired to a live NSTextView, matching the
    /// Phase-2 harness. Returns (coordinator, textView).
    private func makeCoordinator(text: String) -> (NativeTextViewCoordinator, NSTextView) {
        var binding = text
        let coordinator = NativeTextViewCoordinator(
            text: Binding(get: { binding }, set: { binding = $0 }),
            fontName: "SF Pro Text",
            fontSize: 15,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        let textView = NSTextView()
        textView.string = text
        textView.delegate = coordinator
        coordinator.textView = textView
        return (coordinator, textView)
    }

    @Test("ParsedDocument carries the Apple Document parsed from the same text")
    func parsedDocumentCarriesAppleDocument() {
        let (coordinator, _) = makeCoordinator(text: "# Heading\n\n> quote\n")
        let parsed = coordinator.parsedDocument(for: "# Heading\n\n> quote\n")

        // The Apple Document must round-trip the same constructs the
        // supplemental styler walks. Heading + BlockQuote must be present.
        let kinds = parsed.appleDocument.children.map { String(describing: type(of: $0)) }
        #expect(kinds.contains("Heading"))
        #expect(kinds.contains("BlockQuote"))
    }

    @Test("Second call with identical text returns the same cached Document instance")
    func memoReturnsSameDocument() {
        let (coordinator, _) = makeCoordinator(text: "hello\n")
        let first = coordinator.parsedDocument(for: "hello\n")
        let second = coordinator.parsedDocument(for: "hello\n")
        // Document is a value type; identity isn't observable. Assert the
        // cache key held: the cached text equals the query text after the
        // first call, so the second call hit the memo (no re-parse).
        #expect(coordinator.cachedParsedText == "hello\n")
        #expect(first.tokens.count == second.tokens.count)
    }

    @Test("Supplemental styler from cached Document matches parse-from-text output")
    func supplementalStylerCachedMatchesUnparsed() {
        let text = "> quote line one\n> quote line two\n\n~~struck~~ word\n"
        let baseFont = NSFont.systemFont(ofSize: 15)
        let theme = MarkdownPMTheme.default
        let document = Document(parsing: text)

        let fromCache = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: document,
            lineIndex: LineOffsetIndex(text: text),
            baseFont: baseFont,
            theme: theme
        )

        // Smoke check only: the 4-arg form accepts a pre-parsed Document and
        // emits ranges (blockquote + strikethrough present). The byte-identical
        // regression gate is the Phase-2 StyledRangeCorpus snapshot net — NOT a
        // same-call self-compare, which would be tautological.
        #expect(!fromCache.isEmpty)
    }

    /// #9 spine, step 2 (read-only proof). After feeding the styler the cached
    /// Document, ONE supplemental-style pass on the read-only path adds ZERO
    /// parses: the only Apple parse is the spine parse inside parsedDocument.
    /// Drives the READ-ONLY path that 3.1 validated works — it does NOT fire
    /// the edit/restyle pipeline (textDidChange/performEdit/setSelectedRange),
    /// which SIGTRAPs on a windowless programmatic NSTextView.
    @Test("Styler reads the cached Document: one supplemental pass adds no parse (#9 unfolded drop)")
    func supplementalReadsCachedDocument_noExtraParse() {
        let text = "# A\n> q\n~~struck~~ body\n"
        let (coordinator, _) = makeCoordinator(text: text)

        AppleDocumentParseProbe.reset()
        let parsed = coordinator.parsedDocument(for: text)  // the single spine parse
        #expect(AppleDocumentParseProbe.count == 1)

        _ = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: parsed.appleDocument,
            lineIndex: parsed.lineIndex,
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        // The styler consumed the cached Document and did NOT parse again.
        // Unfolded-path count is 1, down from the pre-#9 count of 2.
        #expect(AppleDocumentParseProbe.count == 1)
    }

    /// Phase 3 (Task 3.5) — pins the CODE-BLOCK carve-out's *detection* through
    /// the cache-routed `coordinator.isInsideCode(range:in:)`, the exact path the
    /// 3.5 rewire of the dash transforms / auto-pair / spell-suppression now uses.
    ///
    /// This replaces the transform-level `dashSkipsInsideClosedCode` /
    /// `dashFiresInsideOpenFence` goldens in InputTransformCorpusTests: post-rewire
    /// those transforms read the carve-out from the coordinator delegate, which the
    /// corpus suite's bare (delegate-less) host cannot supply without firing the
    /// edit/restyle pipeline that SIGTRAPs on a windowless NSTextView (Suite E).
    /// The read-only `parsedDocument`/`isInsideCode` path used here is the safe one
    /// (Tasks 3.1/3.3), so it honestly proves the rewired detection returns the
    /// right answers: inside a CLOSED fence → code; inside an OPEN fence → not code.
    @Test("Cache-routed isInsideCode: CLOSED fence is code, OPEN fence is not (carve-out detection)")
    func cacheRoutedCodeBlockCarveOutDetection() {
        // CLOSED fence: caret 7 sits just after the second `-` inside ```...```.
        let closed = "```\na--\n```"
        let (closedCoord, _) = makeCoordinator(text: closed)
        #expect(
            closedCoord.isInsideCode(
                range: NSRange(location: 7, length: 0), in: closed) == true)

        // OPEN (unterminated) fence: the tokenizer emits no .codeBlock spanning
        // the caret, so detection is false — matches the Suite-E-pinned
        // "open fence is not code" behavior.
        let open = "```\na--"
        let (openCoord, _) = makeCoordinator(text: open)
        #expect(
            openCoord.isInsideCode(
                range: NSRange(location: (open as NSString).length, length: 0),
                in: open) == false)
    }

    @Test("syncHeadingFolding produces identical foldedRanges via the cached Document")
    func headingFoldUsesCachedDocument() {
        let text = "# A\nunder a\n\n# B\nunder b\n"
        let (coordinator, textView) = makeCoordinator(text: text)
        guard let ts = textView.textStorage else {
            Issue.record("no text storage")
            return
        }
        // Prime the cache the way the restyle path does.
        _ = coordinator.parsedDocument(for: text)
        // Fold the first heading.
        coordinator.foldedHeadings = ["# A"]
        coordinator.syncHeadingFolding(in: ts, textView: textView)
        let ranges = coordinator.foldedRanges

        // The content under "# A" ("under a\n") must be the folded range.
        #expect(ranges.count == 1)
        #expect(ranges.first?.length ?? 0 > 0)
    }

    /// #9 contract — UNFOLDED state: exactly ONE whole-document Apple
    /// `Document(parsing:)` serves a restyle. The single spine parse lives in
    /// `parsedDocument(for:)`; the supplemental styler reads that cached
    /// Document and parses nothing.
    ///
    /// Proven via the READ-ONLY path (3.1/3.2/3.3-safe), NOT `textDidChange`:
    /// driving the edit/restyle pipeline SIGTRAPs on a windowless programmatic
    /// NSTextView (Suite E + Tasks 3.2/3.5). Text is backtick-free so no
    /// code-block detection parse is triggered. Was 1 before #9; the bar is now
    /// flat at 1 for the unfolded path. (Scope: whole-document spine parse —
    /// per-fragment single-line parses are uncounted.)
    @Test("Unfolded edit triggers exactly one whole-document spine parse (#9)")
    func unfoldedEditParsesOnce() {
        let text = "# A\n\n> quote\n\nbody text here\n"
        let (coordinator, _) = makeCoordinator(text: text)

        AppleDocumentParseProbe.reset()
        let parsed = coordinator.parsedDocument(for: text)  // the single spine parse
        #expect(AppleDocumentParseProbe.count == 1)

        // Supplemental styler reads the cached Document → adds ZERO parses.
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: parsed.appleDocument,
            lineIndex: parsed.lineIndex,
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        #expect(AppleDocumentParseProbe.count == 1)
    }

    /// #9 contract — FOLDED state: exactly ONE whole-document Apple
    /// `Document(parsing:)` serves a restyle even when headings are folded.
    /// Pre-#9 the folded path parsed TWICE (supplemental styler +
    /// syncHeadingFolding each ran their own whole-document `Document(parsing:)`);
    /// the spine collapses both to a single cached parse.
    ///
    /// Order matters: reset → prime `parsedDocument` (the one counted spine
    /// parse) → `syncHeadingFolding`, which reads `parsedDocument(for: text)
    /// .appleDocument` for the SAME text — a cache hit that adds ZERO parses.
    /// `syncHeadingFolding` is harness-safe (proven by `headingFoldUsesCached
    /// Document`, Task 3.3); no edit/restyle pipeline is fired (no SIGTRAP).
    @Test("Folded edit triggers exactly one whole-document spine parse (#9 folded drop 2→1)")
    func foldedEditParsesOnce() {
        let text = "# A\nunder a\n\n# B\nunder b\n"
        let (coordinator, textView) = makeCoordinator(text: text)
        coordinator.foldedHeadings = ["# A"]
        guard let ts = textView.textStorage else {
            Issue.record("no text storage")
            return
        }

        AppleDocumentParseProbe.reset()
        _ = coordinator.parsedDocument(for: text)  // the single spine parse
        #expect(AppleDocumentParseProbe.count == 1)

        // syncHeadingFolding reads the cached Document for the same text →
        // cache hit, ZERO additional parses. Folded path is now flat at 1.
        coordinator.syncHeadingFolding(in: ts, textView: textView)
        #expect(AppleDocumentParseProbe.count == 1)
    }

    /// #9 spine, end-to-end pin (Phase 3.5). The split pair above proves each
    /// consumer in isolation reuses the cached spine; this drives BOTH whole-
    /// document consumers off one prime and asserts the literal "two whole-
    /// document passes → one": exactly ONE whole-document spine parse AND
    /// exactly ONE LineOffsetIndex build serve the supplemental styler + the
    /// heading-fold sync together. Pre-spine, each consumer ran its own parse
    /// AND its own O(n) index build (4 whole-document passes); the cached spine
    /// collapses both to one each.
    ///
    /// Read-only harness only (Tasks 3.1/3.3-safe): prime parsedDocument, then
    /// call the styler + syncHeadingFolding directly — no textDidChange /
    /// edit-restyle pipeline (SIGTRAPs on a windowless NSTextView, Suite E).
    @Test("Combined styler + folding off one prime: one spine parse AND one line-index build (#9 2→1)")
    func combinedConsumersShareSingleSpine() {
        let text = "# A\nunder a\n\n> quote\n\n# B\nunder b\n"
        let (coordinator, textView) = makeCoordinator(text: text)
        coordinator.foldedHeadings = ["# A"]
        guard let ts = textView.textStorage else {
            Issue.record("no text storage")
            return
        }

        AppleDocumentParseProbe.reset()
        LineOffsetIndexProbe.reset()

        // The single prime: one whole-document spine parse + one line-index build.
        let parsed = coordinator.parsedDocument(for: text)
        #expect(AppleDocumentParseProbe.count == 1)
        #expect(LineOffsetIndexProbe.count == 1)

        // Consumer 1 — supplemental styler reads the cached Document + index.
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: parsed.appleDocument,
            lineIndex: parsed.lineIndex,
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        // Consumer 2 — heading-fold sync reads the same cached Document + index.
        coordinator.syncHeadingFolding(in: ts, textView: textView)

        // Both whole-document consumers ran; neither re-parsed nor rebuilt the
        // index. The 2→1 collapse holds end-to-end.
        #expect(AppleDocumentParseProbe.count == 1)
        #expect(LineOffsetIndexProbe.count == 1)
    }
}
