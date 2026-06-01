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

    /// Create the heading-fold hover tracking area on the first
    /// `updateTrackingAreas` call (which AppKit invokes once the view is
    /// in a window) and leave it alone after that. The `.inVisibleRect`
    /// option auto-tracks the visible rect across scroll / resize, so the
    /// prior tear-down + recreate cycle on every AppKit tick was waste —
    /// the area moves with the visible region for free.
    ///
    /// `mouseMoved` events fire only while the cursor is inside this
    /// area and the window is key.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if headingFoldHoverTrackingArea != nil { return }
        let area = NSTrackingArea(
            rect: .zero,  // ignored when `.inVisibleRect` is set
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

    // MARK: - Unified hit-test

    /// Result of resolving a view-point against a heading row. Hover,
    /// cursor swap, and click toggle all consume this — previously each
    /// site recomputed the same fragment lookup + Stage 0/1/2 detection
    /// + key disambiguation + chevron-rect math from scratch on every
    /// mouseMoved (~3× duplicate work per pointer motion).
    struct HeadingHitTest {
        let fragment: NSTextLayoutFragment
        let nsRange: NSRange
        let key: String
        let chevronRect: CGRect
    }

    /// Single hit-test consumed by hover, cursor swap, and chevron click.
    /// Returns `nil` when `viewPoint` doesn't land on a heading row.
    /// Y-based fragment lookup so the entire row is the hover zone
    /// including the left gutter where the chevron draws.
    func headingHitTest(at viewPoint: CGPoint) -> HeadingHitTest? {
        guard let textLayoutManager = textLayoutManager,
            let textStorage = textStorage,
            let coordinator = delegate as? NativeTextViewCoordinator
        else { return nil }

        let containerY = viewPoint.y - textContainerOrigin.y
        guard let fragment = headingFragment(atContainerY: containerY, in: textLayoutManager),
            let nsRange = fragment.nsRange,
            nsRange.location < textStorage.length
        else { return nil }

        let nsText = textStorage.string as NSString
        let fragmentString = nsText.substring(with: nsRange)
        let insideCodeBlock = coordinator.isFragmentRangeInsideCodeBlock(nsRange)
        guard MarkdownDetection.isHeadingLine(fragmentString, isInsideCodeBlock: insideCodeBlock)
        else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: nsRange.location, length: 0))
        let key = NativeTextViewCoordinator.disambiguatedHeadingKey(
            forLineRange: lineRange, in: nsText
        )
        guard let rect = chevronViewRect(for: fragment) else { return nil }
        return HeadingHitTest(fragment: fragment, nsRange: nsRange, key: key, chevronRect: rect)
    }

    // MARK: - Hover update + clear

    /// Set `hoveredHeadingKey` to the heading under the cursor (if any),
    /// or clear it. Pure wrapper around `headingHitTest(at:)`.
    private func updateHeadingFoldHover(at viewPoint: CGPoint) {
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return }
        applyHoveredHeadingKey(headingHitTest(at: viewPoint)?.key, in: coordinator)
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
            let textStorage = textStorage,
            let hit = headingHitTest(at: viewPoint)
        else {
            return false
        }
        // 6pt tolerance around the 12pt glyph — keeps the chevron clickable
        // without making the hit zone bleed into the heading text on the
        // right side or onto adjacent rows above/below.
        guard hit.chevronRect.insetBy(dx: -6, dy: -6).contains(viewPoint) else {
            return false
        }

        let key = hit.key
        let willBeFolded: Bool
        if coordinator.foldedHeadings.contains(key) {
            coordinator.foldedHeadings.remove(key)
            willBeFolded = false
        } else {
            coordinator.foldedHeadings.insert(key)
            willBeFolded = true
        }
        // Propagate the new value through the FRESH binding to viewModel
        // (the callback was installed by the most recent `updateNSView`
        // call so it closes over the current render's $foldedHeadings).
        // Without this, the click-handler mutation stays local to the
        // coordinator and never reaches the view model or frontmatter.
        coordinator.onFoldedHeadingsChanged?(coordinator.foldedHeadings)

        // Synchronous fold reconcile so the collapse / expand happens on
        // the same frame as the click. applyFoldStateIfChanged routes
        // through syncHeadingFolding which calls invalidateFoldLayout on
        // the affected range; the content-manager `shouldEnumerate`
        // delegate then skips elements that intersect `foldedRanges`.
        // Decision 2 unfocus + a second-pass invalidate (when the caret
        // sat inside the freshly-folded range) live inside
        // `applyFoldStateIfChanged` itself — without that second pass,
        // the first invalidate runs with the caret anchoring the element
        // and AppKit overrides `shouldEnumerate` to keep the caret's
        // fragment alive, defeating the fold until the caret naturally
        // moves out.
        coordinator.applyFoldStateIfChanged(in: textStorage, textView: self)
        // Kick off the 200ms rotation animation for the chevron. Per-tick
        // paragraphStyle nudges drive the heading row's redraw with the
        // interpolated angle until the animation completes.
        coordinator.startChevronAnimation(
            forHeadingKey: key, toFolded: willBeFolded, textView: self
        )
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
    /// inflated chevron rect). Pure wrapper around `headingHitTest(at:)`.
    private func isPointInsideHeadingChevronHitZone(_ viewPoint: CGPoint) -> Bool {
        guard let hit = headingHitTest(at: viewPoint) else { return false }
        return hit.chevronRect.insetBy(dx: -6, dy: -6).contains(viewPoint)
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
