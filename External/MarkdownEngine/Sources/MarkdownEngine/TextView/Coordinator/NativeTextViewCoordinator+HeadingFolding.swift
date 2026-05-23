//
//  NativeTextViewCoordinator+HeadingFolding.swift
//  MarkdownEngine
//
//  Pommora addition: foldable-headings service. Translates the user's
//  `foldedHeadings: Set<String>` (exact heading source lines like `"## Foo"`)
//  into runtime `foldedRanges: [NSRange]` covering the source content under
//  each folded heading.
//
//  Sole writer of `coordinator.foldedRanges` — the renderer reads this set
//  to decide whether to collapse a fragment to zero height. Renderer +
//  service agree by construction because both routes funnel through
//  `MarkdownDetection.foldableHeadings` (`.claude/Guidelines/Markdown.md` L2).
//
//  Triggers:
//    1. `rebuildTextStorageAndStyle` (initial-load + full rebuild) and
//       `restyleTextView` (per-edit hot path) call `syncHeadingFolding`
//       after `syncHRVisibility`.
//    2. `NativeTextViewWrapper.updateNSView` calls `applyFoldStateIfChanged`
//       inside its text-unchanged early-return so fold-only updates
//       (chevron clicks) get picked up.
//

import AppKit
import Markdown

extension NativeTextViewCoordinator {

    // MARK: - Redraw-trigger helpers

    /// Find the source-line NSRange for an exact heading key (e.g. `"## Foo"`)
    /// by walking the document line-by-line. O(N); used from low-frequency
    /// paths (hover transition, animation start).
    static func headingLineRange(forKey key: String, in nsText: NSString) -> NSRange? {
        var location = 0
        while location < nsText.length {
            let line = nsText.lineRange(for: NSRange(location: location, length: 0))
            // `trimmingCharacters(in: .newlines)` handles LF / CR / CRLF
            // uniformly. Two-step `hasSuffix("\n")` / `hasSuffix("\r")` fails
            // on CRLF because Swift treats `\r\n` as one grapheme cluster.
            let lineText = nsText.substring(with: line).trimmingCharacters(in: .newlines)
            if lineText == key { return line }
            let next = line.location + line.length
            if next <= location { break }
            location = next
        }
        return nil
    }

    /// Force a re-draw of a heading's fragment by writing the existing
    /// `.paragraphStyle` back to its line range. The write posts
    /// `NSTextStorageDidProcessEditingNotification`, which the layout
    /// manager uses to invalidate the fragment AND cause its `draw(at:in:)`
    /// to re-run on the next display pass.
    ///
    /// `invalidateLayout` alone doesn't actually re-run the imperative draw
    /// method — TextKit 2's fragment-rendering cache only refreshes through
    /// the NSTextStorage edit cascade. Same trigger HR sync uses.
    func nudgeHeading(forKey key: String, in textView: NSTextView) {
        guard let ts = textView.textStorage else { return }
        let nsText = ts.string as NSString
        guard let lineRange = Self.headingLineRange(forKey: key, in: nsText) else { return }
        Self.nudgeAttributes(in: ts, range: lineRange)
    }

    /// Re-write the existing `.paragraphStyle` over `range` so `endEditing()`
    /// posts the edit notification without changing any visible attribute.
    /// Caller is responsible for batching multiple nudges inside a single
    /// `beginEditing` / `endEditing` transaction if they're hot-pathed.
    static func nudgeAttributes(in ts: NSTextStorage, range: NSRange) {
        guard range.length > 0, range.location + range.length <= ts.length else { return }
        let existing =
            ts.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
            as? NSParagraphStyle ?? NSParagraphStyle.default
        ts.beginEditing()
        ts.addAttribute(.paragraphStyle, value: existing, range: range)
        ts.endEditing()
    }

    /// Walk the document AST, find every foldable top-level heading, and
    /// rebuild `foldedRanges` from the subset whose keys appear in the
    /// `foldedHeadings` binding. After updating the range cache, applies
    /// fold-hide ATTRIBUTES to currently-folded ranges — tiny font + zero
    /// line-height paragraphStyle + clear foregroundColor — so the layout
    /// pass naturally produces a near-zero-height fragment frame.
    ///
    /// Why attribute writes (not a `layoutFragmentFrame` getter override):
    /// `NSTextLayoutFragment.layoutFragmentFrame` is a STORED property; the
    /// layout manager calls `setLayoutFragmentFrame:` during layout and
    /// uses the stored value for positioning subsequent fragments. A getter
    /// override only affects external queries — TextKit 2's internal
    /// positioning chain doesn't see it, which is why the override approach
    /// produced asymmetric collapse/expand behavior (expand worked via
    /// natural overflow propagation, collapse silently kept stale Y
    /// positions). Same pattern HRVisibility uses for the `---` dashes.
    func syncHeadingFolding(in ts: NSTextStorage, textView: NSTextView) {
        // Fast path: no folds requested → guarantee an empty result without
        // walking the AST. Common case for unedited pages.
        if foldedHeadings.isEmpty {
            if !foldedRanges.isEmpty { foldedRanges = [] }
            lastSyncedFoldedHeadings = []
            return
        }

        let text = ts.string
        let nsText = text as NSString
        let document = Markdown.Document(parsing: text)
        let headings = MarkdownDetection.foldableHeadings(in: document, nsText: nsText)

        // Reduce to just the content ranges of headings the user has folded.
        // Zero-length content ranges (e.g. a heading at the very end of the
        // document with nothing under it) DO get included — the fold-state
        // membership is the source of truth, and the user expects the
        // toggle + chevron icon to register even when there's nothing
        // visible to collapse. `applyFoldHideAttributes` skips zero-length
        // ranges via its `range.length > 0` guard.
        var newRanges: [NSRange] = []
        newRanges.reserveCapacity(headings.count)
        for heading in headings where foldedHeadings.contains(heading.key) {
            newRanges.append(heading.contentRange)
        }

        // Cheap structural-equality check — avoid `==` since NSRange's
        // Equatable conformance via `NSEqualRanges` does the same work but
        // requires Array's element comparator. Inline lengths-then-locations
        // is allocation-free.
        let unchanged =
            newRanges.count == foldedRanges.count
            && zip(newRanges, foldedRanges).allSatisfy({
                $0.location == $1.location && $0.length == $1.length
            })
        if !unchanged {
            foldedRanges = newRanges
        }
        lastSyncedFoldedHeadings = foldedHeadings
    }

    // MARK: - Chevron rotation animation

    /// Static target angle (radians) for a heading's chevron given its fold
    /// state. `chevron.right` rotated 0° (folded — natural orientation) or
    /// +π/2 (expanded — geometrically identical to `chevron.down`). The
    /// positive angle reads as clockwise visually because `NSGraphicsContext`
    /// uses a flipped Y axis here.
    static let chevronFoldedAngle: CGFloat = 0
    static let chevronExpandedAngle: CGFloat = .pi / 2

    /// Current chevron rotation angle for a heading. If an animation is in
    /// flight for this key, interpolates between its start and target via
    /// an ease-in-out curve; otherwise returns the static target angle for
    /// the current fold state. Called from the renderer at draw time.
    func currentChevronAngle(forHeadingKey key: String, isFolded: Bool) -> CGFloat {
        let staticTarget: CGFloat =
            isFolded ? Self.chevronFoldedAngle : Self.chevronExpandedAngle
        guard let anim = chevronAnimations[key] else { return staticTarget }
        let elapsed = Date.timeIntervalSinceReferenceDate - anim.startTime
        if elapsed >= anim.duration { return anim.targetAngle }
        if elapsed <= 0 { return anim.startAngle }
        let t = elapsed / anim.duration
        let eased = Self.easeInOut(t)
        return anim.startAngle + (anim.targetAngle - anim.startAngle) * CGFloat(eased)
    }

    /// Cubic ease-in-out: matches the implicit curve SwiftUI DisclosureGroup
    /// uses for its chevron rotation, without the spring overshoot.
    private static func easeInOut(_ t: Double) -> Double {
        if t < 0.5 { return 2 * t * t }
        let r = -2 * t + 2
        return 1 - (r * r) / 2
    }

    /// Kick off (or replace) an in-flight rotation animation. Captures the
    /// current visible angle as the start so toggling mid-animation
    /// interpolates from wherever the chevron is right now (smooth on fast
    /// double-clicks). Caches the heading's line range so the 60Hz tick
    /// doesn't re-walk the document per frame.
    func startChevronAnimation(
        forHeadingKey key: String,
        toFolded isFolded: Bool,
        textView: NSTextView
    ) {
        let previousFoldState = !isFolded
        let startAngle = currentChevronAngle(forHeadingKey: key, isFolded: previousFoldState)
        let targetAngle: CGFloat =
            isFolded ? Self.chevronFoldedAngle : Self.chevronExpandedAngle
        let headingRange: NSRange? = textView.textStorage.flatMap { ts in
            Self.headingLineRange(forKey: key, in: ts.string as NSString)
        }
        chevronAnimations[key] = ChevronAnimation(
            startAngle: startAngle,
            targetAngle: targetAngle,
            startTime: Date.timeIntervalSinceReferenceDate,
            duration: 0.2,
            headingRange: headingRange
        )
        ensureChevronAnimationTimer(textView: textView)
    }

    /// Boot the per-coordinator chevron animation timer if it isn't running.
    /// Idempotent — every fold toggle calls this; subsequent calls no-op
    /// while the timer is alive.
    private func ensureChevronAnimationTimer(textView: NSTextView) {
        guard chevronAnimationTimer == nil else { return }
        // @objc selector form sidesteps Swift 6 strict-concurrency's
        // `@Sendable` capture check on block-form Timer closures. Pattern
        // mirrored from `+Services.swift`.
        let timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(NativeTextViewCoordinator.chevronAnimationTick(_:)),
            userInfo: textView,
            repeats: true
        )
        // .common keeps the animation ticking during scroll / window drag /
        // menu interaction.
        RunLoop.main.add(timer, forMode: .common)
        chevronAnimationTimer = timer
    }
}

extension NativeTextViewCoordinator {
    /// Per-tick chevron animation handler. Drops completed animations,
    /// nudges the heading paragraph for each in-flight + just-completed
    /// chevron so its `draw(at:in:)` re-runs with the new interpolated
    /// angle, and stops the timer once the dict drains.
    @objc func chevronAnimationTick(_ timer: Timer) {
        let now = Date.timeIntervalSinceReferenceDate
        // Collect-then-remove. Mutating the dict mid-iteration is UB and
        // froze the first animation per page during dev.
        var completed: [(key: String, range: NSRange?)] = []
        for (key, anim) in chevronAnimations where (now - anim.startTime) >= anim.duration {
            completed.append((key, anim.headingRange))
        }
        for (key, _) in completed {
            chevronAnimations.removeValue(forKey: key)
        }

        if let textView = timer.userInfo as? NSTextView, let ts = textView.textStorage {
            ts.beginEditing()
            for (_, anim) in chevronAnimations {
                if let range = anim.headingRange,
                    range.length > 0,
                    range.location + range.length <= ts.length
                {
                    let existing =
                        ts.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                        as? NSParagraphStyle ?? NSParagraphStyle.default
                    ts.addAttribute(.paragraphStyle, value: existing, range: range)
                }
            }
            for (_, range) in completed {
                if let range = range,
                    range.length > 0,
                    range.location + range.length <= ts.length
                {
                    let existing =
                        ts.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                        as? NSParagraphStyle ?? NSParagraphStyle.default
                    ts.addAttribute(.paragraphStyle, value: existing, range: range)
                }
            }
            ts.endEditing()
        }
        if chevronAnimations.isEmpty {
            timer.invalidate()
            chevronAnimationTimer = nil
        }
    }

    // MARK: - Fold-toggle invalidation

    /// Fold-toggle entry: detects a `foldedHeadings` change that didn't
    /// accompany a text edit (chevron click) and re-runs the AST walk.
    /// Phase-1 stub — Phase 3 reinstates layout invalidation via
    /// content-manager elision (Foldable-Headings-Rebuild.md Task 3.3).
    func applyFoldStateIfChanged(in ts: NSTextStorage, textView: NSTextView) {
        guard foldedHeadings != lastSyncedFoldedHeadings else { return }
        syncHeadingFolding(in: ts, textView: textView)
    }

    // MARK: - Caret skip across folded ranges

    /// Push the caret / selection out of any folded range it currently
    /// intersects. Two cases:
    ///   - Selection start lies INSIDE a folded range → push to the fold's
    ///     end so the caret lands on the first character after the fold.
    ///   - Selection extends FROM before the fold INTO it (a nonzero-length
    ///     range that crosses the fold's leading edge) → collapse to the
    ///     fold's start so the user doesn't accidentally select invisible
    ///     content.
    ///
    /// Called from the top of `textViewDidChangeSelection` so any selection
    /// move that lands inside a fold is corrected before the rest of the
    /// delegate logic runs against the stale selection. Also called from
    /// `applyFoldStateIfChanged` so newly-folded regions push the caret out
    /// without waiting for the user to nudge it.
    ///
    /// Returns `true` when a push happened so the caller can short-circuit
    /// (the synchronous `setSelectedRange` re-fires the delegate; the
    /// recursive call does the real work against the corrected selection).
    /// Guarded by `isPushingCaretOutOfFold` so the recursive entry no-ops.
    @discardableResult
    func skipCaretOutOfFoldedRangesIfNeeded(_ textView: NSTextView) -> Bool {
        guard !isPushingCaretOutOfFold else { return false }
        guard !foldedRanges.isEmpty else { return false }

        let sel = textView.selectedRange()
        let selStart = sel.location
        let selEnd = sel.location + sel.length
        var pushTarget: Int? = nil

        for folded in foldedRanges {
            let foldStart = folded.location
            let foldEnd = folded.location + folded.length

            // Case A — caret/selection origin lies inside the folded range.
            if selStart >= foldStart && selStart < foldEnd {
                pushTarget = foldEnd
                break
            }
            // Case B — nonzero-length selection extending into the fold from
            // before it. Collapse at the leading edge so no folded content is
            // selected.
            if sel.length > 0 && selStart < foldStart && selEnd > foldStart {
                pushTarget = foldStart
                break
            }
        }

        guard let target = pushTarget else { return false }

        isPushingCaretOutOfFold = true
        defer { isPushingCaretOutOfFold = false }
        // NSTextView clamps location to documentRange automatically.
        textView.setSelectedRange(NSRange(location: target, length: 0))
        return true
    }

    /// When folding causes the caret to land inside (or its leading
    /// selection edge to land inside) a now-folded range, drop focus from
    /// the text view rather than relocate the caret. Per Nathan: don't
    /// jump the caret to the next visible line — leaving the user without
    /// a caret feels less invasive than the editor grabbing their cursor
    /// mid-thought. They can click anywhere to re-acquire focus.
    ///
    /// Distinct from `skipCaretOutOfFoldedRangesIfNeeded` (used by the
    /// selection-change delegate path), which pushes the caret past the
    /// fold so arrow-key navigation can traverse around it. Both can't
    /// share a single helper because the appropriate response differs
    /// per origin event.
    @discardableResult
    func unfocusCaretIfInsideFoldedRange(_ textView: NSTextView) -> Bool {
        guard !foldedRanges.isEmpty else { return false }
        let sel = textView.selectedRange()
        let selStart = sel.location
        for folded in foldedRanges {
            let foldStart = folded.location
            let foldEnd = folded.location + folded.length
            if selStart >= foldStart && selStart < foldEnd {
                textView.window?.makeFirstResponder(nil)
                return true
            }
        }
        return false
    }
}
