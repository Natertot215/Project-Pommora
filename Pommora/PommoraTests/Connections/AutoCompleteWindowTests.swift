import Foundation
import Testing

@testable import Pommora

/// Pins `AutoCompleteWindow.highlightSplit` — the PURE helper that splits a
/// candidate title into the matched leading prefix + the remaining tail. The
/// split is purely positional (prefix-matching already guarantees the leading
/// `queryLength` characters matched), with `queryLength` clamped to the title's
/// length. The SwiftUI view body itself is verified visually via the
/// Component-Library showcase (not unit-testable).
@Suite("AutoCompleteWindowTests")
struct AutoCompleteWindowTests {

    /// Normal case — the leading `queryLength` characters are the matched prefix.
    @Test func splitsAtQueryLength() {
        let (matched, rest) = AutoCompleteWindow.highlightSplit(title: "Project Atlas", queryLength: 3)
        #expect(matched == "Pro")
        #expect(rest == "ject Atlas")
    }

    /// Zero-length query → nothing matched; the whole title is the remainder.
    @Test func zeroLengthMatchesNothing() {
        let (matched, rest) = AutoCompleteWindow.highlightSplit(title: "Project Atlas", queryLength: 0)
        #expect(matched == "")
        #expect(rest == "Project Atlas")
    }

    /// Query longer than the title clamps → the whole title is matched, rest empty.
    @Test func clampsToTitleLength() {
        let (matched, rest) = AutoCompleteWindow.highlightSplit(title: "Pro", queryLength: 99)
        #expect(matched == "Pro")
        #expect(rest == "")
    }

    /// The split is PURELY positional — it cuts by length, not by content. Even a
    /// query whose case differs from the title (prefix-match is case-insensitive
    /// upstream) splits at the same index, preserving the title's original casing.
    @Test func splitIsPositionalNotContentBased() {
        let (matched, rest) = AutoCompleteWindow.highlightSplit(title: "Protocol Notes", queryLength: 3)
        #expect(matched == "Pro")  // title's casing preserved, not the query's
        #expect(rest == "tocol Notes")
        // Same index regardless of what the query string actually was.
        #expect(String(matched) + String(rest) == "Protocol Notes")
    }
}
