import AppKit
import Foundation
import Testing
@testable import MarkdownPM

/// Pins the SHIPPED per-level heading-size scale (divergence D-HEAD-2).
///
/// `styleHeadings` (MarkdownStyler+TextStyling.swift:22-43) reads the
/// multiplier for a level from `HeadingStyle.fontMultiplier(for:)`
/// (default `[2.0, 1.5, 1.17, 1.0, 0.83, 0.67]`, H1...H6 — see
/// MarkdownEditorConfiguration.swift:257) and emits a bold `.font` over the
/// heading CONTENT range sized `baseFont.pointSize * multiplier`.
///
/// These assertions lock the CURRENT pointSizes (base fontSize 16) so the
/// Phase-5 flip to `[2.0, 1.75, 1.5, 1.25, 1.15, 1.0]` can no longer slip the
/// characterization net silently — D-HEAD-2 becomes an explicit, failing diff.
@MainActor
@Suite("HeadingSizeCorpus")
struct HeadingSizeCorpusTests {

    /// Base point size every expected value is derived from (× the multiplier).
    private static let baseFontSize: CGFloat = 16

    /// Returns the `.font` pointSize emitted over the heading content character.
    /// For `# A` ... `###### A` the single content char `A` sits at utf16 index
    /// `level + 1` (level `#`s + one space).
    private func headingContentPointSize(level: Int) -> CGFloat? {
        let hashes = String(repeating: "#", count: level)
        let text = "\(hashes) A"
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        let active = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: 0, length: 0),
            tokens: tokens,
            in: text as NSString
        )
        let ranges = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro Text",
            fontSize: Self.baseFontSize,
            caretLocation: 0,
            activeTokenIndices: active,
            precomputedTokens: tokens
        )
        let contentLocation = level + 1
        for r in ranges where NSLocationInRange(contentLocation, r.range) {
            if let font = r.attributes[.font] as? NSFont {
                return font.pointSize
            }
        }
        return nil
    }

    // Observed pointSizes at base fontSize 16 — the SHIPPED scale. Each equals
    // 16 × the default multiplier, i.e. the array [2.0,1.5,1.17,1.0,0.83,0.67].
    @Test("H1 content font is 32.0pt (16 × 2.0)")
    func h1() { #expect(headingContentPointSize(level: 1) == 32.0) }

    @Test("H2 content font is 24.0pt (16 × 1.5)")
    func h2() { #expect(headingContentPointSize(level: 2) == 24.0) }

    @Test("H3 content font is 18.72pt (16 × 1.17)")
    func h3() { #expect(headingContentPointSize(level: 3) == 18.72) }

    @Test("H4 content font is 16.0pt (16 × 1.0)")
    func h4() { #expect(headingContentPointSize(level: 4) == 16.0) }

    @Test("H5 content font is 13.28pt (16 × 0.83)")
    func h5() { #expect(headingContentPointSize(level: 5) == 13.28) }

    @Test("H6 content font is 10.72pt (16 × 0.67)")
    func h6() { #expect(headingContentPointSize(level: 6) == 10.72) }

    /// Whole-scale guard: the six pointSizes, divided by the base size, ARE the
    /// shipped multiplier array. Locks the scale as a set so a partial Phase-5
    /// edit can't pass the per-level cases while drifting the array.
    @Test("Derived multiplier array is the shipped [2.0,1.5,1.17,1.0,0.83,0.67]")
    func derivedMultiplierArray() {
        let observed = (1...6).compactMap { headingContentPointSize(level: $0) }
        #expect(observed.count == 6)
        let multipliers = observed.map { $0 / Self.baseFontSize }
        let expected: [CGFloat] = [2.0, 1.5, 1.17, 1.0, 0.83, 0.67]
        for (got, want) in zip(multipliers, expected) {
            #expect(abs(got - want) < 0.0001)
        }
    }
}
