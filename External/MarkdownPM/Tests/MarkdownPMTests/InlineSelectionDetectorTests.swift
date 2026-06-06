//
//  InlineSelectionDetectorTests.swift
//  MarkdownPMTests
//
//  Pins the inline-token DETECTOR — `inlineTokenContext(at:parsed:codeTokens:
//  text:)` — the pure-over-(text, caret, parsed-tokens) classifier the caret-
//  move path uses to decide which inline token the caret is inside. E5-A adds
//  the `{{Title}}` item-link arm beside the existing `[[Name]]` wiki-link and
//  `![[Name]]` image-embed arms; this suite proves the new arm classifies an
//  item-link AND that the shared mapping (`InlineTokenContext.selectionKind`)
//  reports `.itemLink`, while leaving the wiki-link arm unchanged.
//
//  Harness: the read-only `parsedDocument(for:)` path on a delegate-less
//  programmatic NSTextView (mirrors ParseSpineTests) — it does NOT fire the
//  edit/restyle pipeline (SIGTRAPs on a windowless NSTextView). The detector
//  is a pure function over the parsed tokens + caret, so this exercises the
//  real classification without a live caret event.
//

import AppKit
import Markdown
import SwiftUI
import Testing

@testable import MarkdownPM

@MainActor
@Suite("InlineSelectionDetectorTests")
struct InlineSelectionDetectorTests {

    /// Mirrors the ParseSpineTests harness: a coordinator wired to a live (but
    /// delegate-less / windowless) NSTextView, used only through the read-only
    /// `parsedDocument(for:)` + `inlineTokenContext(...)` path.
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

    /// Run the detector for `text` with the caret at `caret`.
    private func detect(_ text: String, caret: Int) -> NativeTextViewCoordinator.InlineTokenContext? {
        let (coordinator, _) = makeCoordinator(text: text)
        let parsed = coordinator.parsedDocument(for: text)
        return coordinator.inlineTokenContext(
            at: caret,
            parsed: parsed,
            codeTokens: parsed.codeTokens,
            text: text as NSString
        )
    }

    @Test("Caret inside {{Beta}} classifies as .itemLink with selectionKind .itemLink")
    func caretInsideItemLinkClassifies() {
        // "alpha {{Beta}} gamma" — `{{` opens at index 6, interior "Beta" spans 8..12.
        let text = "alpha {{Beta}} gamma"
        // Caret in the middle of "Beta" (index 9, between 'B' and 'e').
        guard let context = detect(text, caret: 9) else {
            Issue.record("detector returned nil for a caret inside {{Beta}}")
            return
        }
        guard case .itemLink(let token) = context else {
            Issue.record("expected .itemLink, got \(context)")
            return
        }
        #expect(context.selectionKind == .itemLink)
        // The token's content range covers the interior placeholder "Beta".
        #expect((text as NSString).substring(with: token.contentRange) == "Beta")
    }

    @Test("Display range for the {{Beta}} item-link spans the full token (markers + Beta interior)")
    func itemLinkDisplayRangeSpansFullToken() {
        let text = "alpha {{Beta}} gamma"
        let (coordinator, _) = makeCoordinator(text: text)
        let parsed = coordinator.parsedDocument(for: text)
        guard
            let context = coordinator.inlineTokenContext(
                at: 9, parsed: parsed, codeTokens: parsed.codeTokens, text: text as NSString)
        else {
            Issue.record("detector returned nil for a caret inside {{Beta}}")
            return
        }
        // `{{ }}` markers are 2 chars (parallel to `[[ ]]`) → openingMarkerLength 2.
        // selectionDisplayRange spans marker-to-marker (the same shape it produces
        // for a `[[ ]]` wiki-link), so it covers the whole `{{Beta}}` token.
        let displayRange = coordinator.selectionDisplayRange(for: context.token, openingMarkerLength: 2)
        #expect((text as NSString).substring(with: displayRange) == "{{Beta}}")
        // The interior placeholder "Beta" lives on the token's contentRange.
        #expect((text as NSString).substring(with: context.token.contentRange) == "Beta")
    }

    @Test("Caret inside [[Page]] still classifies as .wikiLink (unchanged path)")
    func wikiLinkPathUnchanged() {
        let text = "see [[Page]] now"
        // Caret inside "Page" (index 7).
        guard let context = detect(text, caret: 7) else {
            Issue.record("detector returned nil for a caret inside [[Page]]")
            return
        }
        guard case .wikiLink = context else {
            Issue.record("expected .wikiLink, got \(context)")
            return
        }
        #expect(context.selectionKind == .wikiLink)
    }

    @Test("InlineTokenContext.selectionKind maps each case to its matching InlineSelectionKind")
    func selectionKindMappingIsExhaustive() {
        let token = MarkdownToken(
            kind: .itemLink,
            range: NSRange(location: 0, length: 8),
            contentRange: NSRange(location: 2, length: 4),
            markerRanges: [NSRange(location: 0, length: 2), NSRange(location: 6, length: 2)]
        )
        #expect(NativeTextViewCoordinator.InlineTokenContext.itemLink(token: token).selectionKind == .itemLink)
        #expect(NativeTextViewCoordinator.InlineTokenContext.wikiLink(token: token).selectionKind == .wikiLink)
        #expect(NativeTextViewCoordinator.InlineTokenContext.imageEmbed(token: token).selectionKind == .imageEmbed)
    }
}
