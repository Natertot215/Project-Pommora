//
//  NativeTextView+HeadingFoldHover.swift
//  MarkdownEngine
//
//  Pommora addition: hover detection for the foldable-headings chevron.
//  Maintains an NSTrackingArea covering the visible text area + handles
//  `mouseMoved` by hit-testing the cursor's Y coordinate against the
//  document's layout fragments. When the row under the cursor is a heading
//  paragraph, the coordinator's `hoveredHeadingKey` is set to that
//  heading's source-line key; the renderer reads this state to decide
//  whether to draw the chevron over that fragment.
//
//  Y-based hit-testing (rather than (x, y)) deliberately extends the hover
//  zone across the full row width — including the left gutter where the
//  chevron will draw — so the chevron stays visible while the user moves
//  to click it. The "hover anywhere on the heading line" UX from the plan.
//

import AppKit

extension NativeTextView {

    /// Rebuild the heading-fold hover tracking area whenever the visible
    /// rect changes (scroll, resize, etc.). AppKit calls `updateTrackingAreas`
    /// on every scroll / live-resize tick, so this keeps the area aligned
    /// with what the user can actually see. `mouseMoved` events fire only
    /// while the cursor is inside this area and the window is key.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = headingFoldHoverTrackingArea {
            removeTrackingArea(existing)
            headingFoldHoverTrackingArea = nil
        }
        let area = NSTrackingArea(
            rect: visibleRect,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        headingFoldHoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let viewPoint = convert(event.locationInWindow, from: nil)
        updateHeadingFoldHover(at: viewPoint)
        updateHeadingChevronCursor(at: viewPoint)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHeadingFoldHover()
    }

    // MARK: - Hover update + clear

    /// Hit-test the layout fragment under the cursor's Y coordinate. When
    /// the resulting fragment is an ATX heading line (per Stage 0/1/2
    /// detection), set `hoveredHeadingKey` to its exact source line.
    /// Otherwise clear hover state.
    ///
    /// Y-based (not point-based) so the entire row is the hover zone —
    /// keeps the chevron stable while the user crosses from text into the
    /// left gutter to click it.
    private func updateHeadingFoldHover(at viewPoint: CGPoint) {
        guard let coordinator = delegate as? NativeTextViewCoordinator,
            let textLayoutManager = textLayoutManager,
            let textStorage = textStorage
        else {
            clearHeadingFoldHover()
            return
        }
        let containerY = viewPoint.y - textContainerOrigin.y
        guard let fragment = headingFragment(atContainerY: containerY, in: textLayoutManager),
            let nsRange = fragmentNSRange(for: fragment, in: textLayoutManager)
        else {
            applyHoveredHeadingKey(nil, in: coordinator)
            return
        }

        let nsText = textStorage.string as NSString
        // Use the fragment's own range, not paragraphRange, so we get the
        // heading line including its `## ` marker as the styler stored it.
        guard nsRange.location < nsText.length else {
            applyHoveredHeadingKey(nil, in: coordinator)
            return
        }
        let fragmentString = nsText.substring(with: nsRange)
        let insideCodeBlock = headingFragmentInsideCodeBlock(
            textStorage: textStorage, range: nsRange)
        guard MarkdownDetection.isHeadingLine(fragmentString, isInsideCodeBlock: insideCodeBlock)
        else {
            applyHoveredHeadingKey(nil, in: coordinator)
            return
        }

        let key = fragmentString.trimmingCharacters(in: .newlines)
        applyHoveredHeadingKey(key, in: coordinator)
    }

    private func clearHeadingFoldHover() {
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return }
        applyHoveredHeadingKey(nil, in: coordinator)
    }

    /// Diff-and-store helper: assigns the new key only when it changes, and
    /// invalidates layout for the affected heading fragments so TextKit 2
    /// actually re-calls their `draw(at:in:)`.
    ///
    /// `setNeedsDisplay` and `invalidateRenderingAttributes` both fail here —
    /// the former marks the view dirty but TextKit 2 still skips fragments
    /// it thinks haven't changed; the latter only invalidates the rendering-
    /// attribute validator's cache (not the imperative draw method).
    /// `invalidateLayout(for:)` on the heading's line range marks the
    /// fragment's layout stale, which forces the layout manager to re-run
    /// the draw on the next render pass — and the draw method reads
    /// `coordinator.hoveredHeadingKey` to decide whether to render the
    /// chevron. The trigger is independent of caret position by design.
    private func applyHoveredHeadingKey(
        _ newKey: String?, in coordinator: NativeTextViewCoordinator
    ) {
        guard coordinator.hoveredHeadingKey != newKey else { return }
        let oldKey = coordinator.hoveredHeadingKey
        coordinator.hoveredHeadingKey = newKey
        // Nudge both the previously-hovered AND newly-hovered headings so
        // the OLD chevron disappears (mouse leaving) and the NEW chevron
        // appears (mouse entering) in the same render cycle. Without the
        // old-key nudge, the chevron would stick on screen until something
        // else cascaded through.
        if let oldKey = oldKey {
            coordinator.nudgeHeading(forKey: oldKey, in: self)
        }
        if let newKey = newKey {
            coordinator.nudgeHeading(forKey: newKey, in: self)
        }
    }

    // MARK: - Layout-fragment lookup

    /// Find the first heading layout fragment whose vertical extent contains
    /// `containerY`. Iterates forward from document start with `.ensuresLayout`
    /// so we hit only laid-out fragments. Stops as soon as a fragment's
    /// minY exceeds the target Y (fragments are in document order, which is
    /// also Y order in our single-column layout).
    private func headingFragment(
        atContainerY containerY: CGFloat,
        in textLayoutManager: NSTextLayoutManager
    ) -> NSTextLayoutFragment? {
        guard let docStart = textLayoutManager.textContentManager?.documentRange.location
        else { return nil }
        var found: NSTextLayoutFragment? = nil
        textLayoutManager.enumerateTextLayoutFragments(
            from: docStart, options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > containerY {
                return false
            }
            if frame.minY <= containerY, containerY < frame.maxY, frame.height > 0 {
                found = fragment
                return false
            }
            return true
        }
        return found
    }

    /// Convert a fragment's `rangeInElement` into a document-relative NSRange,
    /// mirroring the pattern used inside `MarkdownTextLayoutFragment.fragmentNSRange`.
    /// Returns nil when the content manager isn't an NSTextContentStorage
    /// (atypical) or the range can't be resolved.
    private func fragmentNSRange(
        for fragment: NSTextLayoutFragment,
        in textLayoutManager: NSTextLayoutManager
    ) -> NSRange? {
        guard
            let contentStorage = textLayoutManager.textContentManager
                as? NSTextContentStorage
        else { return nil }
        let docStart = contentStorage.documentRange.location
        let start = contentStorage.offset(from: docStart, to: fragment.rangeInElement.location)
        let end = contentStorage.offset(from: docStart, to: fragment.rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// Mirror of `MarkdownTextLayoutFragment.hasCodeBlockBackground` from
    /// outside the fragment — checks whether the paragraph's first character
    /// carries a backgroundColor matching the syntax highlighter's code-block
    /// background. Stage-0 guard for `isHeadingLine`.
    private func headingFragmentInsideCodeBlock(
        textStorage: NSTextStorage, range: NSRange
    ) -> Bool {
        guard range.location < textStorage.length else { return false }
        guard
            let bgColor = textStorage.attribute(
                .backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
        else { return false }
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return false }
        let currentBg = coordinator.configuration.services.syntaxHighlighter.backgroundColor()
        guard let lhs = bgColor.usingColorSpace(.deviceRGB),
            let rhs = currentBg.usingColorSpace(.deviceRGB)
        else { return false }
        let tol: CGFloat = 0.03
        return abs(lhs.redComponent - rhs.redComponent) < tol
            && abs(lhs.greenComponent - rhs.greenComponent) < tol
            && abs(lhs.blueComponent - rhs.blueComponent) < tol
    }

    // MARK: - Chevron click

    /// Test whether a left-mouseDown at `viewPoint` lands inside a heading's
    /// chevron rect. When it does, toggle that heading's membership in
    /// `foldedHeadings` (which propagates up through the binding to the
    /// view model + frontmatter + save pipeline), then synchronously
    /// reconcile `foldedRanges` + invalidate layout so the collapse / expand
    /// happens before this mouse event returns — SwiftUI's binding-driven
    /// update path would otherwise lag the click by one render cycle.
    ///
    /// Returns `true` when the click was consumed (caller skips `super`,
    /// preventing NSTextView from repositioning the caret onto the heading
    /// line as a side effect of the click).
    func handleHeadingChevronClick(at viewPoint: CGPoint) -> Bool {
        guard let coordinator = delegate as? NativeTextViewCoordinator,
            let textLayoutManager = textLayoutManager,
            let textStorage = textStorage
        else { return false }
        let containerY = viewPoint.y - textContainerOrigin.y
        guard let fragment = headingFragment(atContainerY: containerY, in: textLayoutManager),
            let nsRange = fragmentNSRange(for: fragment, in: textLayoutManager)
        else { return false }
        guard nsRange.location < textStorage.length else { return false }
        let fragmentString = (textStorage.string as NSString).substring(with: nsRange)
        let insideCodeBlock = headingFragmentInsideCodeBlock(
            textStorage: textStorage, range: nsRange)
        guard
            MarkdownDetection.isHeadingLine(
                fragmentString, isInsideCodeBlock: insideCodeBlock)
        else { return false }

        guard let rect = chevronViewRect(for: fragment) else { return false }
        // 6pt tolerance around the 12pt glyph — keeps the chevron clickable
        // without making the hit zone bleed into the heading text on the
        // right side or onto adjacent rows above/below.
        let hit = rect.insetBy(dx: -6, dy: -6)
        guard hit.contains(viewPoint) else { return false }

        let key = fragmentString.trimmingCharacters(in: .newlines)
        let willBeFolded: Bool
        if coordinator.foldedHeadings.contains(key) {
            coordinator.foldedHeadings.remove(key)
            willBeFolded = false
        } else {
            coordinator.foldedHeadings.insert(key)
            willBeFolded = true
        }

        // Synchronous fold reconcile so the collapse / expand happens on
        // the same frame as the click. applyFoldStateIfChanged handles
        // the attribute-write fold-hide + layout invalidation.
        coordinator.applyFoldStateIfChanged(in: textStorage, textView: self)
        // Kick off the 200ms rotation animation for the chevron. Per-tick
        // paragraphStyle nudges drive the heading row's redraw with the
        // interpolated angle until the animation completes.
        coordinator.startChevronAnimation(
            forHeadingKey: key, toFolded: willBeFolded, textView: self
        )
        // Phase-4 will replace this with conditional unfocus (Decision 2):
        // unconditional resignation here is a temporary stand-in so Phase 1
        // ships green. Final shape: only drop focus when the post-toggle
        // caret would otherwise land inside the freshly-folded range.
        window?.makeFirstResponder(nil)
        return true
    }

    /// Chevron rect in VIEW coordinates for a layout fragment. Mirrors the
    /// renderer's `chevronRect(at:)` via shared `HeadingChevronGeometry`
    /// (Markdown.md L2 — both sites must produce identical rects so the
    /// click hit-test lands on the drawn glyph).
    private func chevronViewRect(for fragment: NSTextLayoutFragment) -> CGRect? {
        guard textLayoutManager?.textContainer != nil,
            let firstLine = fragment.textLineFragments.first
        else { return nil }
        // Renderer's call site passes fragment-local origin; this site uses
        // view-coord origin (textContainerOrigin + fragment's offset).
        let fragmentOrigin = CGPoint(
            x: textContainerOrigin.x + fragment.layoutFragmentFrame.origin.x,
            y: textContainerOrigin.y + fragment.layoutFragmentFrame.origin.y
        )
        return HeadingChevronGeometry.rect(
            fragmentOrigin: fragmentOrigin,
            containerLeading: textContainerOrigin.x,
            firstLineBounds: firstLine.typographicBounds
        )
    }

    // MARK: - Pointer cursor over the chevron

    /// True when `viewPoint` lands inside the chevron hit-zone (the 6pt-
    /// inflated chevron rect) of the heading row at the cursor's Y.
    /// Drives the `pointingHand` cursor swap in `mouseMoved`.
    private func isPointInsideHeadingChevronHitZone(_ viewPoint: CGPoint) -> Bool {
        guard let textLayoutManager = textLayoutManager,
            let textStorage = textStorage
        else { return false }
        let containerY = viewPoint.y - textContainerOrigin.y
        guard let fragment = headingFragment(atContainerY: containerY, in: textLayoutManager),
            let nsRange = fragmentNSRange(for: fragment, in: textLayoutManager)
        else { return false }
        guard nsRange.location < textStorage.length else { return false }
        let fragmentString = (textStorage.string as NSString).substring(with: nsRange)
        let inCodeBlock = headingFragmentInsideCodeBlock(textStorage: textStorage, range: nsRange)
        guard MarkdownDetection.isHeadingLine(fragmentString, isInsideCodeBlock: inCodeBlock)
        else { return false }
        guard let rect = chevronViewRect(for: fragment) else { return false }
        return rect.insetBy(dx: -6, dy: -6).contains(viewPoint)
    }

    /// Set `pointingHand` over the chevron, `iBeam` over the rest of the
    /// editor body. Called from `mouseMoved` on every motion within the
    /// tracking area — the cursor would otherwise stay `pointingHand` after
    /// the mouse leaves the chevron because we don't get an explicit
    /// "cursor exit chevron rect" event.
    func updateHeadingChevronCursor(at viewPoint: CGPoint) {
        if isPointInsideHeadingChevronHitZone(viewPoint) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }
}
