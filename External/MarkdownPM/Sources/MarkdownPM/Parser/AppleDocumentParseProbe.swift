//
//  AppleDocumentParseProbe.swift
//  MarkdownPM
//
//  Behavior-neutral instrumentation: a single chokepoint for the
//  whole-document Apple spine parse — the one feeding both whole-document
//  consumers (AppleASTSupplementalStyler + syncHeadingFolding). Counts
//  invocations so Phase 2 can pin the count and Phase 3 can assert the
//  reduction. The Phase-3 cached spine replaces the call sites; this probe
//  stays as the regression gate.
//
//  SCOPE: this counts ONLY the whole-document spine parse. Per-fragment
//  single-line `Document(parsing:)` calls elsewhere — MarkdownDetection
//  .isThematicBreakLine / .isHeadingLine (Setext suppression) /
//  foldableHeadings(in: String), and MarkdownTextLayoutFragment's blockquote
//  probe — are intentionally NOT routed through this probe: they're cheap
//  single-line parses, not whole-document passes, and are an accepted,
//  uncounted residual.
//
import Foundation
import Markdown

/// Wraps `Markdown.Document(parsing:)` with an invocation counter.
/// Counting is gated to test/DEBUG so production has zero overhead.
enum AppleDocumentParseProbe {
    #if DEBUG
    nonisolated(unsafe) static var count = 0
    static func reset() { count = 0 }
    #endif

    /// Drop-in for `Markdown.Document(parsing: text)` at the two whole-document
    /// call sites. Identical output; increments the counter under DEBUG.
    static func parse(_ text: String) -> Document {
        #if DEBUG
        count += 1
        #endif
        return Document(parsing: text)
    }
}
