//
//  MarkdownTextLayoutFragment.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 12.04.26.
//
//  TextKit 2 replacement for CodeBlockLayoutManager.
//  Draws code-block backgrounds, LaTeX images, and task checkboxes
//  via NSTextLayoutFragment instead of NSLayoutManager glyph overrides.

@preconcurrency import AppKit
import Markdown

// MARK: - Custom attribute keys for rendering overlays

extension NSAttributedString.Key {
    nonisolated static let latexImage = NSAttributedString.Key("LatexRenderedImage")
    nonisolated static let latexBounds = NSAttributedString.Key("LatexImageBounds")
    nonisolated static let latexIsBlock = NSAttributedString.Key("LatexIsBlock")
    nonisolated static let latexBlockOffsetY = NSAttributedString.Key("LatexBlockOffsetY")
    // Historical note: do NOT add a custom NSAttributedString.Key here for any
    // paragraph-level construct (HR, blockquote, etc.). AppKit's attribute
    // inheritance leaks custom flags onto newly-typed chars in ways
    // `shouldChangeTypingAttributes` cannot prevent — the prior HR
    // implementation's `.pommoraThematicBreak` key caused "duplicate HR on
    // every Enter" bugs. Use AST-backed detection at draw time + a
    // caret-awareness service for visibility state. See
    // `.claude/Guidelines/Markdown.md` §6.1.
}

// Pommora vendoring: NSTextLayoutFragment's overridden members are nonisolated
// in the AppKit declaration, but Swift 6 strict concurrency infers our subclass
// as @MainActor (due to AppKit context). We:
//   1. mark the specific overrides `nonisolated` to match the parent,
//   2. declare the class `@unchecked Sendable` so `self` and CGContext can
//      cross into the MainActor.assumeIsolated body without sending-check
//      errors, and
//   3. wrap each override body in `MainActor.assumeIsolated` — safe because
//      TextKit 2 always invokes rendering on the main thread.
// The `@unchecked Sendable` contract is honored at runtime by TextKit 2's
// main-thread guarantee.
final class MarkdownTextLayoutFragment: NSTextLayoutFragment, @unchecked Sendable {

    // MARK: - Initializers (nonisolated to match parent declarations)

    nonisolated override init(textElement: NSTextElement, range: NSTextRange?) {
        super.init(textElement: textElement, range: range)
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - ThematicBreak (Pommora addition)

    /// True when this fragment's text parses to a Markdown ThematicBreak node
    /// at document position. Two-stage check:
    ///   - Stage 0: code-block guard (`---` inside a fenced code block parses
    ///     as ThematicBreak in isolation but visually belongs to the code).
    ///   - Stage 1: cheap string prefilter (nanoseconds) — bails on prose.
    ///   - Stage 2: per-fragment swift-markdown AST parse — canonical answer.
    /// Independent of any custom NSAttributedString attribute (which is what
    /// caused the prior plan's `.pommoraThematicBreak` leak via inheritance).
    ///
    /// **No setext-underline guard.** Per Pommora's design (`CLAUDE.md`:
    /// "Pommora removed Setext H2 support so no markdown-feature conflict"),
    /// `---` ALWAYS renders as HR regardless of what's on the line above —
    /// matching Obsidian/Typora behavior. The per-fragment AST parse correctly
    /// returns ThematicBreak for `---\n` in isolation, so dropping the guard
    /// is structurally correct: AST already gives the desired answer.
    private var hasThematicBreak: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        let fragmentString = ts.attributedSubstring(from: range).string
        return MarkdownDetection.isThematicBreakLine(
            fragmentString,
            isInsideCodeBlock: hasCodeBlockBackground
        )
    }

    /// True when the caret rests inside the paragraph that owns this fragment.
    /// Uses paragraph-start identity to match `syncHRVisibility`'s detection in
    /// the coordinator — no drift possible. The earlier range-intersection +
    /// edge-clause version drifted after Enter (renderer said "still in" while
    /// service said "in next").
    private var caretIsInFragment: Bool {
        guard let textView = nearestTextView(),
            let ts = textStorage,
            let range = fragmentNSRange
        else { return false }
        let nsText = ts.string as NSString
        let caretLocation = min(textView.selectedRange().location, ts.length)
        let caretParagraph = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
        return caretParagraph.location == range.location
    }

    /// Reaches the NSTextView from the layout fragment via the standard
    /// TextKit 2 chain. If this ever returns nil in practice, fall back to a
    /// weak NSTextView reference set during fragment construction.
    private func nearestTextView() -> NSTextView? {
        textLayoutManager?.textContainer?.textView
    }

    // MARK: - Foldable headings (Pommora addition)

    /// Reaches the coordinator from the layout fragment via the standard
    /// TextKit 2 chain → NSTextView → delegate. Returns nil if either link
    /// in the chain is missing (e.g. during teardown).
    @MainActor
    private func nearestCoordinator() -> NativeTextViewCoordinator? {
        nearestTextView()?.delegate as? NativeTextViewCoordinator
    }

    /// Exact source-line string for this fragment with no trailing newline —
    /// the same shape used as the fold-state key. Returns nil when the
    /// fragment has no backing storage (teardown).
    @MainActor
    private var headingFragmentString: String? {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else {
            return nil
        }
        return ts.attributedSubstring(from: range).string
    }

    /// True when this fragment IS an ATX heading line. Three-stage detection
    /// via the shared `MarkdownDetection.isHeadingLine` so renderer + hover
    /// tracker + fold service agree on what counts as a heading (L2).
    @MainActor
    private var hasHeadingMarker: Bool {
        guard let fragmentString = headingFragmentString else { return false }
        return MarkdownDetection.isHeadingLine(
            fragmentString, isInsideCodeBlock: hasCodeBlockBackground
        )
    }

    /// Key for this heading fragment — exact source line stripped of any
    /// trailing newline. Matches `FoldedHeading.key` shape so the renderer
    /// can compare against `coordinator.foldedHeadings` /
    /// `coordinator.hoveredHeadingKey` directly.
    @MainActor
    private var headingKey: String? {
        guard hasHeadingMarker, let fragmentString = headingFragmentString else {
            return nil
        }
        return fragmentString.trimmingCharacters(in: .newlines)
    }

    /// True when this heading is currently under the mouse cursor — the
    /// hover tracker on `NativeTextView` writes `hoveredHeadingKey` and the
    /// renderer reads it. Drives chevron visibility.
    @MainActor
    private var isHoveredHeading: Bool {
        guard hasHeadingMarker,
            let coordinator = nearestCoordinator(),
            let key = headingKey
        else { return false }
        return coordinator.hoveredHeadingKey == key
    }

    /// True when this heading's content is currently collapsed. Determines
    /// chevron orientation (right ▶ for folded, down ▼ for expanded).
    @MainActor
    private var isHeadingFolded: Bool {
        guard let coordinator = nearestCoordinator(), let key = headingKey else { return false }
        return coordinator.foldedHeadings.contains(key)
    }

    /// Chevron draw geometry — gutter rect positioned OUTSIDE the text
    /// container's leading edge, vertically centered on the first line
    /// fragment's mid-Y.
    ///
    /// `point` is the fragment's origin. Two call sites use this with very
    /// different `point` meanings:
    /// 1. `draw(at:in:)` passes the fragment's VIEW-COORD origin → returned
    ///    rect is in view coords (e.g. `(6, midY-6, 12, 12)` for Pommora's
    ///    24pt `textContainerInset`).
    /// 2. `renderingSurfaceBounds` passes `.zero` → returned rect is in
    ///    fragment-LOCAL coords (e.g. `(-18, midY-6, 12, 12)`).
    ///
    /// The math is identical for both because of the identity
    /// `point.x = textContainerOrigin.x + layoutFragmentFrame.origin.x`.
    /// The result is offset accordingly without conditional logic.
    ///
    /// **No clamping to non-negative X.** A `max(0, ...)` guard on this
    /// rect was previously biting `renderingSurfaceBounds`: it forced the
    /// rect's fragment-local X to 0 when the chevron actually drew at -18,
    /// so TextKit 2 clipped the chevron entirely out of the visible
    /// rendering surface. Letting X go negative is correct — the gutter
    /// area lives to the left of the fragment's natural frame, and the
    /// rendering surface must include it.
    @MainActor
    private func chevronRect(at point: CGPoint) -> CGRect? {
        guard textLayoutManager?.textContainer != nil,
            let firstLine = textLineFragments.first
        else { return nil }
        let containerLeading = point.x - layoutFragmentFrame.origin.x
        return HeadingChevronGeometry.rect(
            fragmentOrigin: point,
            containerLeading: containerLeading,
            firstLineBounds: firstLine.typographicBounds
        )
    }

    /// Draws the fold chevron in the left gutter when this fragment is the
    /// hovered heading. Single-glyph rotation: `chevron.right` rotated 0°
    /// (folded) ↔ 90° (expanded). The 90°-rotated `chevron.right` is
    /// geometrically identical to `chevron.down` — same vector path.
    /// Coordinator's chevron animation timer drives the angle interpolation
    /// over 200ms; per-tick paragraphStyle nudge on the heading line forces
    /// `draw(at:in:)` to re-run with the new angle.
    ///
    /// `@MainActor` because the body queries the `@MainActor`-isolated
    /// coordinator. Called from `draw(at:in:)` inside
    /// `MainActor.assumeIsolated` so the isolation is satisfied at runtime.
    @MainActor
    private func drawHeadingChevron(at point: CGPoint, in context: CGContext) {
        guard hasHeadingMarker, isHoveredHeading else { return }
        guard let rect = chevronRect(at: point),
            let coordinator = nearestCoordinator(),
            let key = headingKey
        else { return }

        let angle = coordinator.currentChevronAngle(
            forHeadingKey: key, isFolded: isHeadingFolded
        )

        guard
            let baseSymbol = NSImage(
                systemSymbolName: "chevron.right", accessibilityDescription: nil)
        else { return }
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: NSColor.secondaryLabelColor)
        let symbol =
            baseSymbol.withSymbolConfiguration(sizeConfig.applying(colorConfig)) ?? baseSymbol

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        // Rotate around the chevron's center. Save/restore CGContext state
        // around the transform so the rest of the draw pipeline stays in
        // its original coordinate system.
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: angle)
        context.translateBy(x: -rect.width / 2, y: -rect.height / 2)
        symbol.draw(in: CGRect(origin: .zero, size: rect.size))
    }

    /// Draws a horizontal line in place of the HR's hidden dashes — but only
    /// when the caret is NOT in this fragment (Obsidian-style dynamic syntax).
    /// When the caret is on the line, the service in the coordinator restores
    /// the dashes' visibility and removes paragraphSpacing, so the user sees
    /// the literal `---` text without the line.
    private func drawThematicBreak(at point: CGPoint, in context: CGContext) {
        guard hasThematicBreak else { return }
        guard !caretIsInFragment else { return }

        guard let textContainer = textLayoutManager?.textContainer else { return }
        // Y anchor: first line fragment's typographic midY. Stable across
        // neighbor-induced layout changes — layoutFragmentFrame.height includes
        // (or excludes) extra-line metrics + paragraphSpacing depending on
        // surrounding content. Same expression used in renderingSurfaceBounds.
        guard let firstLine = textLineFragments.first else { return }
        let lineMidY = point.y + firstLine.typographicBounds.midY

        // Body-text width: container minus the two lineFragmentPadding insets.
        let containerWidth = textContainer.size.width - (textContainer.lineFragmentPadding * 2)

        let lineColor = NSColor.separatorColor  // Apple pre-attenuates; no .withAlphaComponent
        let lineThickness: CGFloat = 1.5

        let lineRect = CGRect(
            x: point.x - layoutFragmentFrame.origin.x + textContainer.lineFragmentPadding,
            y: lineMidY - (lineThickness / 2),
            width: containerWidth,
            height: lineThickness
        )

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        lineColor.setFill()
        NSBezierPath(rect: lineRect).fill()
    }

    // MARK: - Dash bullet marker (Pommora addition)

    /// True when this fragment is a `-`-marker bullet item — the source `-` has
    /// been hidden by `MarkdownListHandler.paragraphAttributes` (font 0.1 +
    /// clear color) and we need to overlay a `•` glyph. Three-stage detection
    /// mirroring `hasThematicBreak`:
    ///   - Stage 0: code-block guard.
    ///   - Stage 1: cheap prefilter — trimmed line starts with `-` followed by
    ///     whitespace AND does not contain `[` (excludes task lists).
    ///   - Stage 2: per-fragment AST parse confirms `UnorderedList`.
    ///
    /// Only `-` triggers. `*`, `+`, and legacy `•` render as their literal
    /// characters (no hide, no overlay). Same UX guarantee as task checkboxes:
    /// always-on, no caret-aware reveal.
    private var hasDashBulletMarker: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        let fragmentString = ts.attributedSubstring(from: range).string
        return MarkdownDetection.isDashBulletLine(
            fragmentString,
            isInsideCodeBlock: hasCodeBlockBackground
        )
    }

    /// Document-level NSRange location of the `-` source marker for this
    /// fragment, or `nil` if not found. Walks forward from the fragment's
    /// start, skipping `\t` and ` `, returns the first non-whitespace char's
    /// location (the `-` per `hasDashBulletMarker`'s Stage 1 guarantee).
    private var dashBulletMarkerDocumentLocation: Int? {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return nil }
        let nsText = ts.string as NSString
        let end = min(range.location + range.length, nsText.length)
        for i in range.location..<end {
            let ch = nsText.character(at: i)
            if ch == 0x09 || ch == 0x20 { continue }  // \t or space
            if ch == 0x2D { return i }  // `-`
            return nil
        }
        return nil
    }

    /// Draws a `•` glyph at the location of the hidden source `-` marker.
    /// Always-on (no `caretIsInFragment` guard) — same UX as task checkboxes.
    /// Pixel-aligned on both axes via `backingScaleFactor` to avoid the
    /// invisible-bullet failure mode from Session 13.
    private func drawDashBulletGlyph(at point: CGPoint, in context: CGContext) {
        guard hasDashBulletMarker,
            let markerLoc = dashBulletMarkerDocumentLocation,
            let pos = drawPosition(forDocumentCharAt: markerLoc, point: point)
        else { return }

        let baseFont =
            (textLayoutManager?.textContainer?.textView as? NativeTextView)?.baseFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let theme =
            (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default

        // Bullet glyph at 1.5× body font size for visual prominence.
        // (Apple's default is 1.0× — NSTextList, TextEdit, Notes all match
        // the paragraph's font size — but SF Pro's `•` glyph reads small at
        // body size, so Pommora bumps it.)
        let bulletFont = NSFont.systemFont(ofSize: baseFont.pointSize * 1.5)

        let scale =
            textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        func alignToPixel(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let bulletString = NSAttributedString(
            string: "•",
            attributes: [
                .font: bulletFont,
                .foregroundColor: theme.bodyText,
            ])
        // NSAttributedString.draw(at:) takes the top-left of the bounding rect;
        // baseline lands at point.y + ascender in the flipped coordinate space.
        // Use the bullet font's ascender so the glyph sits on the body baseline.
        let drawPoint = CGPoint(
            x: alignToPixel(pos.x),
            y: alignToPixel(pos.baselineY - bulletFont.ascender))
        bulletString.draw(at: drawPoint)
    }

    // MARK: - Blockquote marker (Pommora addition)

    /// True when this fragment's first non-whitespace character is `>`
    /// AND is followed by space or tab AND the per-fragment AST confirms
    /// a `BlockQuote` child. Three-stage detection mirroring
    /// `hasThematicBreak` (L70-77):
    ///   - Stage 0: code-block guard (a `> foo` inside a fenced block must
    ///     NOT render blockquote chrome).
    ///   - Stage 1: cheap string prefilter scanning the raw fragment text
    ///     (NOT a trimmed copy — trimming would strip the very trailing
    ///     space we need to verify on a `> \n` line with no content). Skip
    ///     leading whitespace, confirm `>`, then confirm next char is
    ///     space or tab. Matches list-activation UX where `-` alone
    ///     doesn't activate until `- `.
    ///   - Stage 2: per-fragment swift-markdown AST parse — canonical answer.
    private var hasBlockquoteMarker: Bool {
        guard !hasCodeBlockBackground,
            let ts = textStorage,
            let range = fragmentNSRange,
            range.length > 0
        else { return false }
        let fragmentString = ts.attributedSubstring(from: range).string

        // Stage 1: scan raw string. Skip leading whitespace, find `>`,
        // require next char to be space or tab.
        let nsFragment = fragmentString as NSString
        var i = 0
        while i < nsFragment.length {
            let c = nsFragment.character(at: i)
            if c == 0x20 || c == 0x09 {
                i += 1
                continue
            }
            break
        }
        guard i < nsFragment.length, nsFragment.character(at: i) == 0x3E else { return false }
        guard i + 1 < nsFragment.length else { return false }
        let next = nsFragment.character(at: i + 1)
        guard next == 0x20 || next == 0x09 else { return false }

        // Stage 2: AST confirms (canonical).
        let document = Markdown.Document(parsing: fragmentString)
        return document.children.contains { $0 is BlockQuote }
    }

    /// Position of this fragment within a multi-paragraph blockquote.
    /// Drives selective corner-rounding for the card AND selective rounded
    /// caps for the vertical bar so the rendering reads as one continuous
    /// visual block across multiple paragraphs.
    enum BlockquotePosition {
        case only  // Single-paragraph quote — round all 4 card corners; bar has rounded caps on both ends.
        case first  // Top of a multi-paragraph quote — round only top card corners; bar rounded cap on top only.
        case middle  // Interior paragraph — no rounding; bar caps flat both ends.
        case last  // Bottom of a multi-paragraph quote — round only bottom card corners; bar rounded cap on bottom only.
    }

    /// Compute this fragment's position within the surrounding blockquote
    /// by peeking one line up and one line down in textStorage and asking
    /// whether the neighbor also starts with `>` (after leading whitespace).
    /// Returns nil when the fragment isn't a blockquote at all.
    private var blockquotePosition: BlockquotePosition? {
        guard hasBlockquoteMarker,
            let ts = textStorage,
            let range = fragmentNSRange
        else { return nil }
        let nsText = ts.string as NSString

        let prevStartsWithQuote = lineStartsWithQuote(
            lineBeforeLocation: range.location, in: nsText)
        let nextStartsWithQuote = lineStartsWithQuote(
            lineAfterLocation: range.location + range.length, in: nsText)

        switch (prevStartsWithQuote, nextStartsWithQuote) {
        case (false, false): return .only
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    /// True when the line ending at (or just before) `location - 1` starts
    /// with `>` after optional leading whitespace.
    private func lineStartsWithQuote(lineBeforeLocation location: Int, in nsText: NSString) -> Bool {
        guard location > 0 else { return false }
        let prevLineRange = nsText.lineRange(for: NSRange(location: location - 1, length: 0))
        return lineRangeStartsWithQuote(prevLineRange, in: nsText)
    }

    /// True when the line starting at `location` starts with `>` after
    /// optional leading whitespace.
    private func lineStartsWithQuote(lineAfterLocation location: Int, in nsText: NSString) -> Bool {
        guard location < nsText.length else { return false }
        let nextLineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        return lineRangeStartsWithQuote(nextLineRange, in: nsText)
    }

    /// True when, after optional leading whitespace, the line starts with
    /// `>` AND the next character is a space or tab. Bare `>` (no space)
    /// is NOT treated as quote-context for position detection, matching
    /// `hasBlockquoteMarker`'s activation gate.
    private func lineRangeStartsWithQuote(_ lineRange: NSRange, in nsText: NSString) -> Bool {
        let end = lineRange.location + lineRange.length
        var i = lineRange.location
        while i < end {
            let c = nsText.character(at: i)
            if c == 0x20 || c == 0x09 {
                i += 1
                continue
            }  // skip spaces/tabs
            guard c == 0x3E else { return false }  // '>'
            // Require `>` followed by space or tab — the activation gate.
            guard i + 1 < end else { return false }
            let next = nsText.character(at: i + 1)
            return next == 0x20 || next == 0x09
        }
        return false
    }

    /// Draws the rounded card (behind text) and the continuous vertical
    /// accent bar (outside the card, in the leading margin) for a
    /// blockquote line. Per-fragment; selective corner rounding driven by
    /// `blockquotePosition` so consecutive fragments butt-joint into a
    /// single visually-contiguous block.
    ///
    /// Coordinate model mirrors `drawCodeBlockBackground` (L391-445):
    /// `x: point.x - layoutFragmentFrame.origin.x` shifts us to the
    /// container's left edge; add `textContainer.lineFragmentPadding` to
    /// land at the leftmost visible text position.
    private func drawBlockquoteCard(at point: CGPoint, in context: CGContext) {
        guard let position = blockquotePosition,
            let textContainer = textLayoutManager?.textContainer
        else { return }

        // Compute the fragment's vertical extent (mirror drawCodeBlockBackground's
        // effective-height computation for trailing empty-line fragments).
        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
            let lastLF = textLineFragments.last,
            lastLF.characterRange.length == 0
        {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        // Pixel-snap y-coords so per-fragment bar segments butt-joint
        // without hairline seams. Same snap formula as drawCodeBlockBackground.
        let scale =
            textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let rawY = point.y
        let rawMaxY = point.y + effectiveHeight
        let snappedY = floor(rawY * scale) / scale
        let snappedMaxY = ceil(rawMaxY * scale) / scale

        // Visual constants (see Page-Editor-Plan.md §"Visual specifications").
    
        let barWidth: CGFloat = 4
        let cornerRadius: CGFloat = 6

        // X anchors — relative to draw context, container-left-aware.
        let containerLeftX = point.x - layoutFragmentFrame.origin.x
        let leftmostVisibleX = containerLeftX + textContainer.lineFragmentPadding
        let barX = leftmostVisibleX
        // Card starts AT the bar's left edge (overlaps the bar entirely).
        // The bar draws AFTER the card so it sits on top visually. This
        // guarantees the card fill extends through the invisible-syntax
        // area between the bar and the body text, regardless of any
        // paragraphStyle indent interactions.
        let cardLeftX = barX

        // Right edge — full container width minus lineFragmentPadding on
        // both sides minus the tailIndent we set in the styler (-8).
        let containerWidth = textContainer.size.width - (textContainer.lineFragmentPadding * 2)
        let cardRightX = containerLeftX + textContainer.lineFragmentPadding + containerWidth - 8

        // Card vertical extent — inflated by `cornerRadius` on rounded
        // ends ONLY. Without inflation, the 6pt rounded corners curve
        // INWARD by 6pt, making the visible card body look shorter
        // than the bar. Inflating pushes the corner curve OUTWARD so the
        // card's straight body extends slightly above/below the text.
        // .middle fragments inflate NEITHER end so they butt-joint
        // flat-to-flat with neighbors (continuous multi-paragraph cards).
        let cardTopY: CGFloat
        let cardBotY: CGFloat
        switch position {
        case .only:
            cardTopY = snappedY - cornerRadius
            cardBotY = snappedMaxY + cornerRadius
        case .first:
            cardTopY = snappedY - cornerRadius
            cardBotY = snappedMaxY
        case .middle:
            cardTopY = snappedY
            cardBotY = snappedMaxY
        case .last:
            cardTopY = snappedY
            cardBotY = snappedMaxY + cornerRadius
        }

        // Bar vertical extent — matches the card exactly (per Nathan:
        // "make the bar align with the height of the fill"). Same
        // position-driven inflation as the card, so the bar's pill caps
        // and the card's rounded corners share the same Y extent.
        let barTopY = cardTopY
        let barBotY = cardBotY

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        // === Draw the card ===
        let cardRect = CGRect(
            x: cardLeftX,
            y: cardTopY,
            width: cardRightX - cardLeftX,
            height: cardBotY - cardTopY
        )
        let cardPath = makeSelectiveRoundedRect(
            cardRect,
            radius: cornerRadius,
            roundTop: position == .only || position == .first,
            roundBottom: position == .only || position == .last
        )
        // Highlight fill — `tertiarySystemFill` is the system's mid-tier
        // semantic fill (more visible than quaternary, less than secondary).
        // Used at native intensity (no alpha modification) — adapts
        // automatically to light/dark mode and accessibility settings.
        NSColor.tertiarySystemFill.setFill()
        cardPath.fill()

        // === Draw the bar ===
        let barRect = CGRect(
            x: barX,
            y: barTopY,
            width: barWidth,
            height: barBotY - barTopY
        )
        let barPath = makeSelectiveRoundedRect(
            barRect,
            radius: barWidth / 2,  // pill-end radius = half the bar width
            roundTop: position == .only || position == .first,
            roundBottom: position == .only || position == .last
        )
        NSColor.secondaryLabelColor.setFill()
        barPath.fill()
    }

    /// Build an `NSBezierPath` with selective top/bottom corner rounding.
    /// When both `roundTop` and `roundBottom` are true, the result equals
    /// `NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)`.
    /// When only one is true, the other two corners are square. When both
    /// are false, returns a plain rect path. Required because the built-in
    /// NSBezierPath roundedRect API rounds all 4 corners uniformly — the
    /// multi-paragraph .first/.middle/.last cases need independent control.
    private func makeSelectiveRoundedRect(
        _ rect: CGRect,
        radius: CGFloat,
        roundTop: Bool,
        roundBottom: Bool
    ) -> NSBezierPath {
        let path = NSBezierPath()
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        // Top edge — start from top-left.
        if roundTop {
            path.move(to: CGPoint(x: minX, y: minY + r))
            path.appendArc(
                withCenter: CGPoint(x: minX + r, y: minY + r),
                radius: r,
                startAngle: 180, endAngle: 270, clockwise: false)
            path.line(to: CGPoint(x: maxX - r, y: minY))
            path.appendArc(
                withCenter: CGPoint(x: maxX - r, y: minY + r),
                radius: r,
                startAngle: 270, endAngle: 360, clockwise: false)
        } else {
            path.move(to: CGPoint(x: minX, y: minY))
            path.line(to: CGPoint(x: maxX, y: minY))
        }

        // Right edge + bottom — flow down to bottom-right.
        if roundBottom {
            path.line(to: CGPoint(x: maxX, y: maxY - r))
            path.appendArc(
                withCenter: CGPoint(x: maxX - r, y: maxY - r),
                radius: r,
                startAngle: 0, endAngle: 90, clockwise: false)
            path.line(to: CGPoint(x: minX + r, y: maxY))
            path.appendArc(
                withCenter: CGPoint(x: minX + r, y: maxY - r),
                radius: r,
                startAngle: 90, endAngle: 180, clockwise: false)
        } else {
            path.line(to: CGPoint(x: maxX, y: maxY))
            path.line(to: CGPoint(x: minX, y: maxY))
        }

        path.close()
        return path
    }

    // MARK: - FB15131180

    /// Maps to TextKit-2's private `extraLineFragmentAttributes` selector so we can pin the trailing extra-line metrics to body font; otherwise a trailing heading paragraph inflates `usageBoundsForTextContainer` by ~30pt when the caret enters it. Pattern from STTextView.
    @objc(extraLineFragmentAttributes)
    dynamic var stExtraLineFragmentAttributes: NSDictionary?

    // MARK: - Rendering surface

    /// Extend rendering bounds for code-block backgrounds (full container width)
    /// and block images drawn below text via paragraphSpacing.
    nonisolated override var renderingSurfaceBounds: CGRect {
        MainActor.assumeIsolated {
            var bounds = super.renderingSurfaceBounds
            if hasCodeBlockBackground {
                let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
                // Extend left to container edge
                bounds.origin.x = -layoutFragmentFrame.origin.x
                bounds.size.width = containerWidth
            }
            // Extend bounds to cover block images that render below the text line
            // (visibleSource mode uses paragraphSpacing to create space for the image).
            for rect in blockImageRects(at: .zero) {
                bounds = bounds.union(rect)
            }
            // Extend bounds for the HR overlay line. Uses the SAME y anchor as
            // drawThematicBreak so the invalidation rect always tracks where the
            // line will draw. Tight (~8pt total) — keeps invalidation cheap.
            if hasThematicBreak {
                let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
                bounds.origin.x = -layoutFragmentFrame.origin.x
                bounds.size.width = containerWidth
                let lineMidY =
                    textLineFragments.first?.typographicBounds.midY
                    ?? (layoutFragmentFrame.height / 2)
                let padding: CGFloat = 3.5
                let lineThickness: CGFloat = 2
                bounds.origin.y = lineMidY - padding - lineThickness / 2
                bounds.size.height = lineThickness + (padding * 2)
            }
            // Extend bounds for the dash-bullet overlay glyph. Small inflated
            // rect around where `drawDashBulletGlyph` will draw. Uses the same
            // 1.2× bullet font multiplier as the draw function so the
            // invalidation rect tracks what's actually rendered.
            if hasDashBulletMarker,
                let markerLoc = dashBulletMarkerDocumentLocation,
                let pos = drawPosition(forDocumentCharAt: markerLoc, point: .zero)
            {
                let baseFont =
                    (textLayoutManager?.textContainer?.textView as? NativeTextView)?.baseFont
                    ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let bulletFont = NSFont.systemFont(ofSize: baseFont.pointSize * 1.5)
                let glyphWidth = ("•" as NSString).size(withAttributes: [.font: bulletFont]).width
                let lineHeight = bulletFont.ascender - bulletFont.descender + bulletFont.leading
                let glyphRect = CGRect(
                    x: pos.x - 2,
                    y: pos.baselineY - bulletFont.ascender - 1,
                    width: glyphWidth + 4,
                    height: lineHeight + 2
                )
                bounds = bounds.union(glyphRect)
            }
            // Extend bounds for the fold chevron when this is a heading
            // fragment. The chevron sits in the LEFT GUTTER outside the
            // text container's natural fragment frame, so the default
            // rendering surface clips it. Always-extended (regardless of
            // hover state) so the invalidation rect doesn't lag behind the
            // hover-driven draw.
            if hasHeadingMarker, let rect = chevronRect(at: .zero) {
                bounds = bounds.union(rect)
            }

            // Extend bounds for the blockquote card + bar. Mirrors the
            // code-block bounds extension shape — left to container edge so
            // the bar (which sits OUTSIDE the natural fragment frame) isn't
            // clipped. Also extend VERTICALLY on rounded-end fragments so
            // the card's inflated corners (drawn by `drawBlockquoteCard`)
            // aren't clipped — the inflation amount is `cornerRadius = 6pt`.
            if hasBlockquoteMarker {
                let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
                bounds.origin.x = -layoutFragmentFrame.origin.x
                bounds.size.width = containerWidth
                if let position = blockquotePosition {
                    let cornerInflation: CGFloat = 6
                    if position == .only || position == .first {
                        bounds.origin.y -= cornerInflation
                        bounds.size.height += cornerInflation
                    }
                    if position == .only || position == .last {
                        bounds.size.height += cornerInflation
                    }
                }
            }
            return bounds
        }
    }

    // MARK: - Drawing

    nonisolated override func draw(at point: CGPoint, in context: CGContext) {
        MainActor.assumeIsolated {
            // 1. Code-block backgrounds (behind text)
            drawCodeBlockBackground(at: point, in: context)

            // 2. Blockquote card + bar (behind text — always-show overlay,
            //    no caret-aware logic; mirrors bullet-glyph pattern)
            drawBlockquoteCard(at: point, in: context)

            // 3. LaTeX images (behind text — hidden markers are invisible anyway)
            drawLatexImages(at: point, in: context)

            // 4. Normal text
            super.draw(at: point, in: context)

            // 5. ThematicBreak horizontal line (covers hidden `---` dashes
            //    when caret is not on the line — see hasThematicBreak +
            //    caretIsInFragment guards)
            drawThematicBreak(at: point, in: context)

            // 6. Dash-bullet glyph (overlays `•` on the hidden source `-`
            //    marker; always-on, same UX as task checkboxes)
            drawDashBulletGlyph(at: point, in: context)

            // 7. Task checkboxes (on top of hidden [ ]/[x] markers)
            drawTaskCheckboxes(at: point, in: context)

            // 8. Foldable-headings chevron: only when this fragment
            //    is a heading AND the mouse is currently hovering it. Hover
            //    state is owned by `NativeTextView+HeadingFoldHover` which
            //    triggers a visible-rect redraw on transitions.
            drawHeadingChevron(at: point, in: context)
        }
    }

    // MARK: - Helpers

    /// NSRange in the document for this fragment's content.
    private var fragmentNSRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let start = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private var textStorage: NSTextStorage? {
        (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
    }

    /// Returns the drawing position for a character at `docIndex` (document-level NSRange location).
    /// `point` is the draw origin passed to `draw(at:in:)`.
    private func drawPosition(
        forDocumentCharAt docIndex: Int, point: CGPoint
    ) -> (x: CGFloat, baselineY: CGFloat, lineHeight: CGFloat)? {
        guard let fragRange = fragmentNSRange else { return nil }
        let localIndex = docIndex - fragRange.location
        guard localIndex >= 0 else { return nil }

        // NSTextLineFragment.typographicBounds.origin.y is already relative to the
        // parent layout fragment, so we use it directly — accumulating per-line
        // heights would double-count the inter-line offset on wrapped lines.
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let charPos = lineFragment.locationForCharacter(at: localIndex)
                let tb = lineFragment.typographicBounds
                return (
                    x: point.x + tb.origin.x + charPos.x,
                    baselineY: point.y + tb.origin.y + charPos.y,
                    lineHeight: tb.height
                )
            }
        }
        return nil
    }

    /// Typographic bounds of the line fragment containing `localIndex`
    /// (index relative to the fragment, not the document).
    private func lineBounds(forLocalIndex localIndex: Int, point: CGPoint) -> CGRect? {
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let tb = lineFragment.typographicBounds
                return CGRect(
                    x: point.x + lineFragment.glyphOrigin.x + tb.origin.x,
                    y: point.y + tb.origin.y,
                    width: tb.width,
                    height: tb.height)
            }
        }
        return nil
    }

    // MARK: - Code Block Background

    private var hasCodeBlockBackground: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        let bgColor = ts.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
        guard let bgColor else { return false }
        return isCodeBlockBackgroundColor(bgColor)
    }

    private func drawCodeBlockBackground(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        // Only fenced code-block fragments get the full-width fill (first char must carry the code background).
        guard let color = ts.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor,
            isCodeBlockBackgroundColor(color)
        else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width

        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
            let lastLF = textLineFragments.last,
            lastLF.characterRange.length == 0
        {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        let scale =
            textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let rawY = point.y
        let rawMaxY = point.y + effectiveHeight
        let snappedY = floor(rawY * scale) / scale
        let snappedMaxY = ceil(rawMaxY * scale) / scale

        // Draw full-width background, clipping out any active selection rects
        // so the system's blue selection highlight remains visible inside code blocks.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let bgRect = CGRect(
            x: point.x - layoutFragmentFrame.origin.x,
            y: snappedY,
            width: containerWidth,
            height: snappedMaxY - snappedY
        )

        let selectionRects = selectionRectsInDrawCoordinates(
            drawPoint: point, snappedY: snappedY, snappedMaxY: snappedMaxY)
        color.setFill()
        if selectionRects.isEmpty {
            NSBezierPath(rect: bgRect).fill()
        } else {
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.appendRect(bgRect)
            for r in selectionRects {
                path.appendRect(r.intersection(bgRect))
            }
            path.fill()
        }
    }

    /// Returns active text-selection rectangles intersecting this fragment, in
    /// the same draw-relative coordinate system used by `drawCodeBlockBackground`.
    private func selectionRectsInDrawCoordinates(
        drawPoint: CGPoint, snappedY: CGFloat, snappedMaxY: CGFloat
    ) -> [CGRect] {
        guard let tlm = textLayoutManager else { return [] }
        var rects: [CGRect] = []

        let dx = drawPoint.x - layoutFragmentFrame.origin.x
        let myRange = self.rangeInElement

        for selection in tlm.textSelections {
            for textRange in selection.textRanges {
                let interStart =
                    textRange.location.compare(myRange.location) == .orderedAscending
                    ? myRange.location : textRange.location
                let interEnd =
                    textRange.endLocation.compare(myRange.endLocation) == .orderedDescending
                    ? myRange.endLocation : textRange.endLocation
                guard interStart.compare(interEnd) == .orderedAscending,
                    let intersection = NSTextRange(location: interStart, end: interEnd)
                else { continue }

                tlm.enumerateTextSegments(in: intersection, type: .selection, options: []) { _, segFrame, _, _ in
                    // Expand vertically to match the bgRect's snapped span so the
                    // even-odd cut-out is geometrically congruent with the fill.
                    let drawRect = CGRect(
                        x: segFrame.origin.x + dx,
                        y: snappedY,
                        width: segFrame.width,
                        height: snappedMaxY - snappedY
                    )
                    rects.append(drawRect)
                    return true
                }
            }
        }
        return rects
    }

    private func isCodeBlockBackgroundColor(_ color: NSColor) -> Bool {
        let highlighter =
            (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.services.syntaxHighlighter
            ?? PlainTextSyntaxHighlighter()
        let currentBg = highlighter.backgroundColor()
        guard let colorRGB = color.usingColorSpace(.deviceRGB),
            let currentBgRGB = currentBg.usingColorSpace(.deviceRGB)
        else { return false }
        let tolerance: CGFloat = 0.03
        return abs(colorRGB.redComponent - currentBgRGB.redComponent) < tolerance
            && abs(colorRGB.greenComponent - currentBgRGB.greenComponent) < tolerance
            && abs(colorRGB.blueComponent - currentBgRGB.blueComponent) < tolerance
    }

    // MARK: - LaTeX / Block Image Helpers

    /// Compute the draw rect for a block image at `attrRange` using `point` as
    /// the draw origin.  Shared by `drawLatexImages` and `blockImageRects` so
    /// bounds and rendering stay in sync.
    private func blockImageDrawRect(
        attrRange: NSRange,
        imageBounds: CGRect,
        blockOffsetY: CGFloat?,
        point: CGPoint
    ) -> CGRect? {
        guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return nil }
        let localIndex = attrRange.location - (fragmentNSRange?.location ?? 0)
        let lb = lineBounds(forLocalIndex: localIndex, point: point)
        let lineHeight = lb?.height ?? pos.lineHeight
        let lineMinY = lb?.origin.y ?? (pos.baselineY - lineHeight)

        let yPosition: CGFloat
        if let blockOffsetY {
            yPosition = lineMinY + blockOffsetY
        } else {
            yPosition = lineMinY + (lineHeight - imageBounds.height) / 2
        }
        return CGRect(
            x: pos.x, y: yPosition,
            width: imageBounds.width, height: imageBounds.height)
    }

    /// Returns the rects of all block images in this fragment, relative to
    /// `point`.  Used by `renderingSurfaceBounds` (with `.zero`) to extend
    /// the surface so images drawn in paragraphSpacing aren't clipped.
    private func blockImageRects(at point: CGPoint) -> [CGRect] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var rects: [CGRect] = []
        ts.enumerateAttribute(.latexImage, in: range, options: []) { value, attrRange, _ in
            guard value is NSImage else { return }
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            guard isBlock else { return }
            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.rectValue ?? .zero
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat
            if let rect = blockImageDrawRect(
                attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point)
            {
                rects.append(rect)
            }
        }
        return rects
    }

    // MARK: - LaTeX Images

    private func drawLatexImages(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        ts.enumerateAttribute(.latexImage, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, let image = value as? NSImage else { return }

            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.rectValue ?? CGRect(origin: .zero, size: image.size)
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat

            guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            let drawRect: CGRect
            if isBlock {
                guard
                    let rect = blockImageDrawRect(
                        attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point)
                else { return }
                drawRect = rect
            } else {
                let descent = imageBounds.origin.y
                drawRect = CGRect(
                    x: pos.x,
                    y: pos.baselineY + descent - imageBounds.height,
                    width: imageBounds.width, height: imageBounds.height)
            }
            image.draw(in: drawRect)
        }
    }

    // MARK: - Task List Checkboxes

    private func drawTaskCheckboxes(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }
        let selectionRanges: [NSRange] = {
            guard let tv = textLayoutManager?.textContainer?.textView else { return [] }
            return tv.selectedRanges.map { $0.rangeValue }.filter { $0.length > 0 }
        }()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        ts.enumerateAttribute(.taskCheckbox, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, value != nil else { return }
            if selectionRanges.contains(where: { NSIntersectionRange($0, attrRange).length > 0 }) { return }

            let isChecked = (value as? Bool) ?? false
            guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            let font =
                (ts.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont)
                ?? (textLayoutManager?.textContainer?.textView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
            let ascent = max(0, font.ascender)
            let descent = max(0, -font.descender)
            let fontHeight = max(1, ceil(ascent + descent))
            let markerWidth = ("[ ]" as NSString).size(withAttributes: [.font: font]).width
            let size = max(1.0, min(floor(fontHeight * 1.2), floor(markerWidth * 1.2)))
            // Align the checkbox's visual center with where the bullet glyph's
            // visual center sits on a plain bullet line. The bullet renders at
            // `pos.x` using a font at `baseFont * 1.5` (see `drawDashBulletGlyph`);
            // its visible dot sits roughly at the glyph's advance-width midpoint.
            // Without this, the checkbox's left edge starts at `pos.x` while the
            // bullet's visible center starts at `pos.x + ~bulletAdvance/2`, so
            // task lines visually sit further right than bullet lines.
            let bulletFont = NSFont.systemFont(ofSize: font.pointSize * 1.5)
            let bulletAdvance = ("•" as NSString).size(withAttributes: [.font: bulletFont]).width
            let boxX = pos.x + (bulletAdvance - size) / 2
            let centerY = pos.baselineY + (descent - ascent) / 2
            let boxY = centerY - size / 2

            let scale =
                textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 2.0
            func alignToPixel(_ value: CGFloat) -> CGFloat {
                (value * scale).rounded(.toNearestOrAwayFromZero) / scale
            }
            let boxRect = CGRect(x: alignToPixel(boxX), y: alignToPixel(boxY), width: size, height: size)
            guard !boxRect.isEmpty, !boxRect.isNull else { return }

            let iconInset = max(0.0, size * 0.01)
            let iconRect = boxRect.insetBy(dx: iconInset, dy: iconInset)
            let symbolName = isChecked ? "checkmark.square.fill" : "square"
            if let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let sizeConfig = NSImage.SymbolConfiguration(pointSize: iconRect.height, weight: .regular)
                let theme =
                    (textLayoutManager?.textContainer?.textView as? NativeTextView)?.configuration.theme ?? .default
                let tint = isChecked ? theme.accentColor : theme.mutedText
                let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: tint)
                let symbolConfig = sizeConfig.applying(colorConfig)
                let symbol = baseSymbol.withSymbolConfiguration(symbolConfig) ?? baseSymbol
                symbol.draw(in: iconRect)
            }
        }
    }
}

// MARK: - Layout Manager Delegate

final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        // Seed body font + paragraphStyle so the trailing fragment doesn't inherit heading metrics (FB15131180).
        if let textView = textLayoutManager.textContainer?.textView as? NativeTextView {
            let baseFont = textView.baseFont
            let para = NSMutableParagraphStyle()
            let lineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: textView.layoutBridge)
            para.minimumLineHeight = ceil(lineHeight) + textView.configuration.paragraph.lineHeightExtraSpacing
            para.paragraphSpacing = ceil(lineHeight * textView.configuration.paragraph.spacingFactor)
            para.paragraphSpacingBefore = 0
            fragment.stExtraLineFragmentAttributes = NSDictionary(dictionary: [
                NSAttributedString.Key.font: baseFont,
                NSAttributedString.Key.foregroundColor: textView.configuration.theme.bodyText,
                NSAttributedString.Key.paragraphStyle: para,
            ])
        }
        return fragment
    }
}
