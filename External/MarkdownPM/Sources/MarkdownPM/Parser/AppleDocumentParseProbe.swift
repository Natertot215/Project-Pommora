//
//  AppleDocumentParseProbe.swift
//  MarkdownPM
//
//  Behavior-neutral instrumentation: a single chokepoint for the two
//  uncached whole-document Apple parses (AppleASTSupplementalStyler +
//  syncHeadingFolding). Counts invocations so Phase 2 can pin the current
//  parse count and Phase 3 can assert the reduction. The Phase-3 cached
//  spine replaces the call sites; this probe stays as the regression gate.
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
