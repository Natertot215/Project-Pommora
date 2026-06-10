//
//  InlineSelectionDetectorTests.swift
//  MarkdownPMTests
//
//  Pins the inline-token DETECTOR — `inlineTokenContext(at:parsed:codeTokens:
//  text:)` — the pure-over-(text, caret, parsed-tokens) classifier the caret-
//  move path uses to decide which inline token the caret is inside: the
//  `[[Name]]` wiki-link and `![[Name]]` image-embed arms, plus the shared
//  mapping (`InlineTokenContext.selectionKind`). `{{ }}` is NOT a syntax
//  (PagesV2 V7) — a caret inside `{{Beta}}` detects nothing.
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

    @Test("Caret inside {{Beta}} detects NOTHING — {{ }} is plain text (PagesV2 V7)")
    func caretInsideCurlyBracesDetectsNothing() {
        // "alpha {{Beta}} gamma" — caret in the middle of "Beta" (index 9).
        if let context = detect("alpha {{Beta}} gamma", caret: 9) {
            Issue.record("expected nil for plain-text {{Beta}}, got \(context)")
        }
    }

    @Test("Placeholder for [[Page]] is the interior 'Page' (wiki-link parity)")
    func wikiLinkPlaceholderIsInterior() {
        let text = "see [[Page]] now"
        let (coordinator, _) = makeCoordinator(text: text)
        let parsed = coordinator.parsedDocument(for: text)
        guard
            let context = coordinator.inlineTokenContext(
                at: 7, parsed: parsed, codeTokens: parsed.codeTokens, text: text as NSString)
        else {
            Issue.record("detector returned nil for a caret inside [[Page]]")
            return
        }
        #expect(coordinator.inlinePlaceholder(for: context.token, in: text as NSString) == "Page")
    }

    @Test("Caret inside [[Page]] classifies as .wikiLink")
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
            kind: .wikiLink,
            range: NSRange(location: 0, length: 8),
            contentRange: NSRange(location: 2, length: 4),
            markerRanges: [NSRange(location: 0, length: 2), NSRange(location: 6, length: 2)]
        )
        #expect(NativeTextViewCoordinator.InlineTokenContext.wikiLink(token: token).selectionKind == .wikiLink)
        #expect(NativeTextViewCoordinator.InlineTokenContext.imageEmbed(token: token).selectionKind == .imageEmbed)
    }
}
