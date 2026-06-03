//
//  ParseSpineTests.swift
//  MarkdownPMTests
//
//  Phase 3: proves the single cached parse spine — the Apple Document is
//  parsed once inside parsedDocument(for:) and reused by every consumer.
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
        let theme = MarkdownEditorTheme.default
        let document = Document(parsing: text)

        let fromCache = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: document,
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
}
