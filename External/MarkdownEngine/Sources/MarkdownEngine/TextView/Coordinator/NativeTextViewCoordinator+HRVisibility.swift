//
//  NativeTextViewCoordinator+HRVisibility.swift
//  MarkdownEngine
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
import Markdown

extension NativeTextViewCoordinator {

    /// Walks the document, finds every ThematicBreak paragraph, and applies
    /// hidden (caret-out) or revealed (caret-in) attributes accordingly.
    /// O(paragraphs) per call — microseconds for typical docs.
    func syncHRVisibility(in ts: NSTextStorage, textView: NSTextView) {
        guard !isSyncingHRVisibility else { return }
        isSyncingHRVisibility = true
        defer { isSyncingHRVisibility = false }

        let nsText = ts.string as NSString
        let selection = textView.selectedRange()
        let caretLocation = min(selection.location, ts.length)
        let caretParagraph = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))

        let (bodyFont, baseParagraphStyle) = TextStylingService.makeBaseFontAndStyle(
            fontName: fontName,
            fontSize: fontSize,
            layoutBridge: layoutBridge,
            configuration: configuration
        )
        let bodyColor = configuration.theme.bodyText

        ts.beginEditing()
        defer { ts.endEditing() }

        var pos = 0
        while pos < ts.length {
            let paragraphRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
            let nextPos = paragraphRange.location + paragraphRange.length
            defer { pos = nextPos > pos ? nextPos : pos + 1 }

            let paragraphString = nsText.substring(with: paragraphRange)
            guard isThematicBreakParagraph(paragraphString, in: ts, paragraphRange: paragraphRange) else { continue }

            let caretIsHere = caretParagraph.location == paragraphRange.location

            if caretIsHere {
                revealHRDashes(
                    in: ts,
                    paragraphRange: paragraphRange,
                    bodyFont: bodyFont,
                    bodyColor: bodyColor,
                    baseParagraphStyle: baseParagraphStyle
                )
            } else {
                applyHRHiding(in: ts, paragraphRange: paragraphRange)
            }
        }
    }

    /// Same two-stage check as the renderer's `hasThematicBreak` — MUST
    /// agree exactly. If the service detects something as HR but the renderer
    /// rejects it (or vice versa), the user sees "dashes hidden but no line
    /// drawn" or "line drawn over visible text".
    ///
    /// **No setext-underline guard.** Per Pommora's design (`CLAUDE.md`:
    /// "Pommora removed Setext H2 support"), `---` ALWAYS renders as HR
    /// regardless of what's on the line above — matching Obsidian/Typora.
    private func isThematicBreakParagraph(
        _ paragraphString: String,
        in ts: NSTextStorage,
        paragraphRange: NSRange
    ) -> Bool {
        // Stage 0 — code-block guard.
        if isInsideCodeBlockParagraph(in: ts, paragraphRange: paragraphRange) {
            return false
        }

        // Stage 1 — prefilter.
        let trimmed = paragraphString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3,
            let first = trimmed.first,
            first == "-" || first == "*" || first == "_"
        else { return false }

        // Stage 2 — AST parse.
        let document = Markdown.Document(parsing: paragraphString)
        return document.children.contains { $0 is ThematicBreak }
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

    /// Caret-out state: hide dashes (font 0.1 + clear color) + apply 16/16pt
    /// paragraph spacing on the full paragraph line range.
    private func applyHRHiding(in ts: NSTextStorage, paragraphRange: NSRange) {
        let hiddenFont = NSFont.systemFont(ofSize: 0.1)
        let nsText = ts.string as NSString

        var i = paragraphRange.location
        let end = paragraphRange.location + paragraphRange.length
        while i < end {
            let ch = nsText.character(at: i)
            if let scalar = Unicode.Scalar(ch),
                scalar == "-" || scalar == "*" || scalar == "_"
            {
                ts.addAttributes(
                    [.font: hiddenFont, .foregroundColor: NSColor.clear],
                    range: NSRange(location: i, length: 1)
                )
            }
            i += 1
        }

        let hrParaStyle = NSMutableParagraphStyle()
        hrParaStyle.paragraphSpacingBefore = 16
        hrParaStyle.paragraphSpacing = 16
        ts.addAttribute(.paragraphStyle, value: hrParaStyle, range: paragraphRange)
    }

    /// Caret-in state: restore body font + body color on dashes; restore base
    /// paragraph style (no extra spacing — feels like editing a normal line).
    private func revealHRDashes(
        in ts: NSTextStorage,
        paragraphRange: NSRange,
        bodyFont: NSFont,
        bodyColor: NSColor,
        baseParagraphStyle: NSParagraphStyle
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
                    [.font: bodyFont, .foregroundColor: bodyColor],
                    range: NSRange(location: i, length: 1)
                )
            }
            i += 1
        }

        ts.addAttribute(.paragraphStyle, value: baseParagraphStyle, range: paragraphRange)
    }
}
