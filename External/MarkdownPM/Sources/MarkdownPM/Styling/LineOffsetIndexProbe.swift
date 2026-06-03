//
//  LineOffsetIndexProbe.swift
//  MarkdownPM
//
//  Behavior-neutral instrumentation mirroring AppleDocumentParseProbe: a
//  single chokepoint for the UTF-8↔UTF-16 LineOffsetIndex build. Phase 3
//  cached the Apple Document once per edit but each consumer (supplemental
//  styler, heading fold) still rebuilt the O(n) line index. Phase 3.5
//  memoizes the index beside the Document in the cached spine and routes
//  every consumer through this probe so a test can assert one build per edit.
//  Counting is gated to DEBUG so production has zero overhead.
//
import Foundation

/// Wraps `LineOffsetIndex(text:)` with an invocation counter.
enum LineOffsetIndexProbe {
    #if DEBUG
    nonisolated(unsafe) static var count = 0
    static func reset() { count = 0 }
    #endif

    /// Drop-in for `LineOffsetIndex(text:)` at the spine build site.
    /// Identical output; increments the counter under DEBUG.
    static func make(_ text: String) -> LineOffsetIndex {
        #if DEBUG
        count += 1
        #endif
        return LineOffsetIndex(text: text)
    }
}
