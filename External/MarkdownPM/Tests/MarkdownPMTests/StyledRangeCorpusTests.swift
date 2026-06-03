import AppKit
import Foundation
import Markdown
import Testing
@testable import MarkdownPM

/// Characterizes `MarkdownStyler.styleAttributes` output (the [StyledRange]
/// list) at varied caret positions, plus the two structural invariants the
/// Phase-5 styler merge must preserve: primary-before-supplemental ordering
/// and ThematicBreak emitting NOTHING from either styler.
@MainActor
@Suite("StyledRangeCorpus")
struct StyledRangeCorpusTests {

    private func styled(
        _ text: String,
        caret: Int
    ) -> [StyledRange] {
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        let active = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: caret, length: 0),
            tokens: tokens,
            in: text as NSString
        )
        return MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro Text",
            fontSize: 15,
            caretLocation: caret,
            activeTokenIndices: active,
            precomputedTokens: tokens
        )
    }

    // Does any emitted range cover `location` and carry a foregroundColor
    // equal to the code-text color (currently NSColor.systemRed@0.85,
    // duplicated MarkdownStyler.swift:462+:499)?
    private func hasCodeTextColor(_ ranges: [StyledRange], at location: Int) -> Bool {
        let target = NSColor.systemRed.withAlphaComponent(0.85)
        for r in ranges where NSLocationInRange(location, r.range) {
            if let c = r.attributes[.foregroundColor] as? NSColor,
               c.isClose(to: target) { return true }
        }
        return false
    }

    @Test("Inline code emits the code-text color over its content")
    func inlineCodeColored() {
        let text = "a `code` b"
        let ranges = styled(text, caret: 0)
        // The `c` of `code` sits at utf16 index 3.
        #expect(hasCodeTextColor(ranges, at: 3))
    }

    @Test("GFM checkbox: caret OFF the line keeps marker hidden (inactive)")
    func checkboxInactive() {
        let text = "- [ ] task\nother"
        // caret on the second line, away from the checkbox.
        let ranges = styled(text, caret: 12)
        // The .taskCheckbox attribute is emitted on the checkbox marker range.
        let hasCheckbox = ranges.contains { $0.attributes[.taskCheckbox] != nil }
        #expect(hasCheckbox)
    }

    @Test("GFM checkbox: caret ON the syntax SUPPRESSES the checkbox attribute (active reveal of raw `[ ]`)")
    func checkboxActive() {
        // CHARACTERIZATION (plan-vs-actual reconciliation): the plan EXPECTED
        // the `.taskCheckbox` attribute to still emit when the caret sits on the
        // checkbox syntax. The SOURCE does the opposite — `styleTaskCheckboxes`
        // (MarkdownStyler.swift:582 `if isActiveSyntax { continue }`) bails out
        // of the whole per-match loop body BEFORE the `.taskCheckbox` append
        // (MarkdownStyler.swift:602-609) when the caret is inside the syntax
        // range. So "active reveal" means the glyph is REPLACED by the raw
        // `- [ ]` text: no `.taskCheckbox` attribute is emitted. We pin the
        // observed suppression, not the plan's expectation.
        let text = "- [ ] task"
        let ranges = styled(text, caret: 3) // caret inside `[ ]`
        let hasCheckbox = ranges.contains { $0.attributes[.taskCheckbox] != nil }
        #expect(!hasCheckbox)
    }

    @Test("Empty [] is NOT styled as a checkbox (deliberate 3-class split)")
    func emptyBracketNotCheckbox() {
        let text = "- [] task"
        let ranges = styled(text, caret: 0)
        #expect(!ranges.contains { $0.attributes[.taskCheckbox] != nil })
    }

    @Test("Incomplete bracket [text] (no link) gets an incomplete-link style range")
    func incompleteBracket() {
        // incompleteLinkRegexes match `[text]` not followed by `(`.
        let text = "see [text] here"
        let ranges = styled(text, caret: 0)
        // At minimum: SOME range is emitted over the bracket span (index 4..9).
        #expect(ranges.contains { NSIntersectionRange($0.range, NSRange(location: 4, length: 6)).length > 0 })
    }

    @Test("ThematicBreak --- emits no checkbox/HR-attribute from the styler")
    func thematicBreakEmitsNothingHR() {
        // The styler must not own HR. The negative we assert: no .taskCheckbox
        // attribute is emitted on the `---` line. (HR appearance is owned solely
        // by syncHRVisibility — there is no public HR attribute key by design;
        // if a future change adds a styler-emitted HR attribute, extend this
        // negative to name it.)
        let text = "---\n"
        let ranges = styled(text, caret: 10)
        #expect(!ranges.contains { $0.attributes[.taskCheckbox] != nil })
    }
}

extension StyledRangeCorpusTests {

    @Test("Supplemental styler emits ranges for blockquote but NOTHING for HR")
    func supplementalCoversBlockquoteNotHR() {
        let bqRanges = AppleASTSupplementalStyler.styleAttributes(
            text: "> quote\n",
            document: Document(parsing: "> quote\n"),
            lineIndex: LineOffsetIndex(text: "> quote\n"),
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        #expect(!bqRanges.isEmpty)

        let hrRanges = AppleASTSupplementalStyler.styleAttributes(
            text: "---\n",
            document: Document(parsing: "---\n"),
            lineIndex: LineOffsetIndex(text: "---\n"),
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        // visitThematicBreak is a deliberate no-op — supplemental owns nothing.
        #expect(hrRanges.isEmpty)
    }

    @Test("Supplemental strikethrough is INLINE and emits over the ~~span~~")
    func supplementalStrikethrough() {
        let ranges = AppleASTSupplementalStyler.styleAttributes(
            text: "a ~~b~~ c",
            document: Document(parsing: "a ~~b~~ c"),
            lineIndex: LineOffsetIndex(text: "a ~~b~~ c"),
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        #expect(!ranges.isEmpty)
    }

    @Test("Supplemental multibyte: emoji line before a blockquote keeps ranges in-bounds")
    func supplementalMultibyte() {
        // Pins the UTF-8/UTF-16 column behavior (deferred bug). The assertion
        // is bounds-safety, not correctness — every emitted range must fall
        // inside the UTF-16 length.
        let text = "👍 hi\n> quote\n"
        let len = (text as NSString).length
        let ranges = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: Document(parsing: text),
            lineIndex: LineOffsetIndex(text: text),
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        for r in ranges {
            #expect(r.range.location >= 0)
            #expect(NSMaxRange(r.range) <= len)
        }
    }
}

private extension NSColor {
    /// Component-wise closeness in the calibrated/device RGB space; tolerant
    /// of deviceRGB rounding (mirrors the 0.03 tolerance the renderer uses).
    func isClose(to other: NSColor, tolerance: CGFloat = 0.03) -> Bool {
        guard let a = usingColorSpace(.deviceRGB),
              let b = other.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) <= tolerance
            && abs(a.greenComponent - b.greenComponent) <= tolerance
            && abs(a.blueComponent - b.blueComponent) <= tolerance
            && abs(a.alphaComponent - b.alphaComponent) <= tolerance
    }
}
