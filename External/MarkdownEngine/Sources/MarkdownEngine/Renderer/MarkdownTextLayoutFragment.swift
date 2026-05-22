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
            return bounds
        }
    }

    // MARK: - Drawing

    nonisolated override func draw(at point: CGPoint, in context: CGContext) {
        MainActor.assumeIsolated {
            // 1. Code-block backgrounds (behind text)
            drawCodeBlockBackground(at: point, in: context)

            // 2. LaTeX images (behind text — hidden markers are invisible anyway)
            drawLatexImages(at: point, in: context)

            // 3. Normal text
            super.draw(at: point, in: context)

            // 4. ThematicBreak horizontal line (covers hidden `---` dashes
            //    when caret is not on the line — see hasThematicBreak +
            //    caretIsInFragment guards)
            drawThematicBreak(at: point, in: context)

            // 5. Dash-bullet glyph (overlays `•` on the hidden source `-`
            //    marker; always-on, same UX as task checkboxes)
            drawDashBulletGlyph(at: point, in: context)

            // 6. Task checkboxes (on top of hidden [ ]/[x] markers)
            drawTaskCheckboxes(at: point, in: context)
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
                let tint = isChecked ? theme.bodyText : theme.mutedText
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
