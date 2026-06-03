//
//  NativeTextViewCoordinator+HRVisibility.swift
//  MarkdownPM
//
//  Pommora addition: Obsidian-style dynamic syntax for Markdown horizontal
//  rules. The styler does NOTHING for ThematicBreak paragraphs (see
//  AppleASTSupplementalStyler.visitThematicBreak). This service is the SOLE
//  writer of HR-specific visual attributes — font/color hiding on the dashes
//  + 16/16pt paragraphSpacing on the full paragraph line range. Attributes
//  are applied only when the caret is OUT of the HR paragraph, so the visual
//  "commit" (dashes hide + line draws + spacing appears) happens on caret-
//  leave (typically Enter) rather than at parser-detection time.
//
//  Triggers:
//    1. textViewDidChangeSelection (already in NativeTextViewCoordinator+
//       TextDelegate.swift) calls `syncHRVisibility` at its end.
//    2. restyleTextView (in NativeTextViewCoordinator+Restyling.swift) calls
//       `syncHRVisibility` after TextStylingService.restyle returns, so the
//       state survives every edit's restyle pass.
//
//  Both triggers use the reentry guard `isSyncingHRVisibility` on the main
//  coordinator class to prevent infinite recursion.
//

import AppKit

extension NativeTextViewCoordinator {

    /// Walks the document, finds every ThematicBreak paragraph, and applies
    /// hidden (caret-out) or revealed (caret-in) attributes accordingly.
    ///
    /// **Use for events that may have changed which paragraphs are HRs**
    /// (initial load, full rebuild, edit-driven restyle). For pure caret
    /// moves where the set of HR paragraphs is unchanged, prefer the scoped
    /// `syncHRVisibility(in:textView:scopedTo:)` — it touches at most two
    /// paragraphs and is the difference between a smooth large file and a
    /// jittery one.
    func syncHRVisibility(in ts: NSTextStorage, textView: NSTextView) {
        guard !isSyncingHRVisibility else { return }
        isSyncingHRVisibility = true
        defer { isSyncingHRVisibility = false }

        let nsText = ts.string as NSString
        let selection = textView.selectedRange()
        let caretLocation = min(selection.location, ts.length)
        let caretParagraph = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))

        let context = makeHRStylingContext()

        ts.beginEditing()
        defer { ts.endEditing() }

        var pos = 0
        while pos < ts.length {
            let paragraphRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
            let nextPos = paragraphRange.location + paragraphRange.length
            defer { pos = nextPos > pos ? nextPos : pos + 1 }

            applyHRSync(
                in: ts,
                paragraphRange: paragraphRange,
                caretParagraph: caretParagraph,
                context: context
            )
        }
    }

    /// Scoped counterpart to the full-document sync — applies HR styling only
    /// to the given paragraphs. Used by `textViewDidChangeSelection` so that
    /// pure caret moves do O(1) work instead of an O(N) document walk.
    ///
    /// HR state is a per-paragraph property; the only paragraphs whose state
    /// can change on a caret-only event are the one the caret left and the
    /// one it entered. Every other HR paragraph in the document is already
    /// in its correct state from the last full walk (initial load + every
    /// edit cycle), so re-walking them is pure overhead. The full
    /// `syncHRVisibility` stays the canonical path for events that could
    /// have changed which paragraphs are HRs in the first place.
    func syncHRVisibility(
        in ts: NSTextStorage,
        textView: NSTextView,
        scopedTo paragraphs: [NSRange]
    ) {
        guard !isSyncingHRVisibility else { return }
        guard !paragraphs.isEmpty else { return }
        isSyncingHRVisibility = true
        defer { isSyncingHRVisibility = false }

        let nsText = ts.string as NSString
        let selection = textView.selectedRange()
        let caretLocation = min(selection.location, ts.length)
        let caretParagraph = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))

        let context = makeHRStylingContext()

        // De-dupe by paragraph start location — callers may pass overlapping
        // ranges (e.g. prev == current when the paragraph didn't change).
        var seen: Set<Int> = []
        let unique: [NSRange] = paragraphs.compactMap { raw in
            guard raw.location != NSNotFound, raw.location <= ts.length else { return nil }
            let safeLocation = min(raw.location, ts.length)
            let para = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            return seen.insert(para.location).inserted ? para : nil
        }
        guard !unique.isEmpty else { return }

        ts.beginEditing()
        defer { ts.endEditing() }

        for paragraphRange in unique {
            applyHRSync(
                in: ts,
                paragraphRange: paragraphRange,
                caretParagraph: caretParagraph,
                context: context
            )
        }
    }

    // MARK: - Sync internals

    /// Bundled body font + style + body color for an HR sync pass. Computed
    /// once per call so the per-paragraph loop doesn't repeat the work.
    ///
    /// `hrParagraphStyle` is applied in BOTH caret-in and caret-out states —
    /// the two states differ only in dash color, never in line metrics or
    /// paragraph spacing. This is what eliminates the vertical layout jump
    /// when the caret crosses into / out of an HR paragraph.
    private struct HRStylingContext {
        let bodyFont: NSFont
        let bodyColor: NSColor
        let hrParagraphStyle: NSParagraphStyle
    }

    private func makeHRStylingContext() -> HRStylingContext {
        let (bodyFont, baseParagraphStyle) = TextStylingService.makeBaseFontAndStyle(
            fontName: fontName,
            fontSize: fontSize,
            layoutBridge: layoutBridge,
            configuration: configuration
        )
        return HRStylingContext(
            bodyFont: bodyFont,
            bodyColor: configuration.theme.bodyText,
            hrParagraphStyle: Self.makeHRParagraphStyle(
                from: baseParagraphStyle, bodyFont: bodyFont
            )
        )
    }

    /// Builds the paragraph style applied to HR paragraphs in BOTH the hidden
    /// and revealed states. Starts from the base paragraph style so any other
    /// editor-wide settings (line spacing, indent, etc.) are preserved, then
    /// overrides only `paragraphSpacingBefore` / `paragraphSpacing`.
    ///
    /// **Margin invariant.** Session 12 picked a perceived ~16pt visual margin
    /// between the drawn rule line and surrounding text. The locked design
    /// achieved that by hiding the dashes (font 0.1pt) and setting both
    /// spacings to 16pt. That worked but coupled the spacing to the line
    /// height — when the caret entered an HR paragraph the dashes inflated
    /// back to body size (~21pt of line height) AND the paragraph style
    /// reverted to the base (zero spacing), so the paragraph collapsed by
    /// ~11pt and the page shifted vertically.
    ///
    /// The new approach keeps dashes at body size in both states and
    /// computes spacing so the visual margin from the rule (drawn at the
    /// line's typographic midY) is constant at 16pt regardless of caret
    /// state: `spacing = max(0, 16 - bodyLineHeight / 2)`. Total paragraph
    /// region works out to ~32pt — matching the locked design — but stays
    /// identical whether the caret is on the line or off it.
    private static func makeHRParagraphStyle(
        from base: NSParagraphStyle,
        bodyFont: NSFont
    ) -> NSParagraphStyle {
        let style =
            (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let lineHeight = bodyFont.ascender - bodyFont.descender + bodyFont.leading
        let targetMarginPerSide: CGFloat = 16
        let spacing = max(0, targetMarginPerSide - (lineHeight / 2))
        style.paragraphSpacingBefore = spacing
        style.paragraphSpacing = spacing
        return style
    }

    /// Apply hidden / revealed HR attributes to a single paragraph based on
    /// whether the caret is currently on it. Shared by both the full-walk
    /// `syncHRVisibility` and the scoped variant so they can't drift.
    /// No-op for paragraphs that aren't ThematicBreaks.
    private func applyHRSync(
        in ts: NSTextStorage,
        paragraphRange: NSRange,
        caretParagraph: NSRange,
        context: HRStylingContext
    ) {
        let paragraphString = (ts.string as NSString).substring(with: paragraphRange)
        guard isThematicBreakParagraph(paragraphString, in: ts, paragraphRange: paragraphRange) else {
            return
        }
        let caretIsHere = caretParagraph.location == paragraphRange.location
        applyHRDashAttributes(
            in: ts,
            paragraphRange: paragraphRange,
            bodyFont: context.bodyFont,
            foregroundColor: caretIsHere ? context.bodyColor : NSColor.clear
        )
        ts.addAttribute(.paragraphStyle, value: context.hrParagraphStyle, range: paragraphRange)
    }

    /// Forwards to the shared `MarkdownDetection.isThematicBreakLine` helper
    /// (one of three pieces of the dynamic-syntax pattern — renderer + service
    /// MUST share their detection per `.claude/Guidelines/Markdown.md` L2).
    /// This wrapper only resolves the service-side Stage 0 result, then hands
    /// the work to the shared detector.
    private func isThematicBreakParagraph(
        _ paragraphString: String,
        in ts: NSTextStorage,
        paragraphRange: NSRange
    ) -> Bool {
        let insideCodeBlock = isInsideCodeBlockParagraph(in: ts, paragraphRange: paragraphRange)
        return MarkdownDetection.isThematicBreakLine(
            paragraphString,
            isInsideCodeBlock: insideCodeBlock
        )
    }

    /// True when the paragraph's first char carries a backgroundColor matching
    /// the active syntax highlighter's code-block background. Mirrors the
    /// renderer's `hasCodeBlockBackground` semantics from outside the layout
    /// fragment.
    private func isInsideCodeBlockParagraph(in ts: NSTextStorage, paragraphRange: NSRange) -> Bool {
        guard paragraphRange.length > 0 else { return false }
        guard
            let bgColor = ts.attribute(.backgroundColor, at: paragraphRange.location, effectiveRange: nil) as? NSColor
        else { return false }
        let highlighter = configuration.services.syntaxHighlighter
        let currentBg = highlighter.backgroundColor()
        guard let colorRGB = bgColor.usingColorSpace(.deviceRGB),
            let currentBgRGB = currentBg.usingColorSpace(.deviceRGB)
        else { return false }
        let tolerance: CGFloat = 0.03
        return abs(colorRGB.redComponent - currentBgRGB.redComponent) < tolerance
            && abs(colorRGB.greenComponent - currentBgRGB.greenComponent) < tolerance
            && abs(colorRGB.blueComponent - currentBgRGB.blueComponent) < tolerance
    }

    /// Sets the dash font + color over the `-`/`*`/`_` glyphs in the HR
    /// paragraph. Font is ALWAYS body-sized — what differs between the hidden
    /// and revealed states is `foregroundColor` (NSColor.clear vs body text
    /// color). Line metrics are therefore identical in both states, which is
    /// what keeps the paragraph from collapsing vertically when the caret
    /// crosses in or out. The drawn HR rule (in `MarkdownTextLayoutFragment.
    /// drawThematicBreak`) sits at the typographic midY of the line, so the
    /// rule's vertical position relative to the dashes' invisible/visible
    /// text is also identical in both states — only the dash glyphs flip
    /// visibility.
    private func applyHRDashAttributes(
        in ts: NSTextStorage,
        paragraphRange: NSRange,
        bodyFont: NSFont,
        foregroundColor: NSColor
    ) {
        let nsText = ts.string as NSString
        var i = paragraphRange.location
        let end = paragraphRange.location + paragraphRange.length
        while i < end {
            let ch = nsText.character(at: i)
            if let scalar = Unicode.Scalar(ch),
                scalar == "-" || scalar == "*" || scalar == "_"
            {
                ts.addAttributes(
                    [.font: bodyFont, .foregroundColor: foregroundColor],
                    range: NSRange(location: i, length: 1)
                )
            }
            i += 1
        }
    }
}
