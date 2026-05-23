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

    // MARK: - AST-based code-block check (shared by renderer + hover)

    /// AST-grounded code-block check for a fragment at `range`. Uses the
    /// coordinator's already-cached `cachedParsedDocument.codeTokens` so the
    /// renderer and hover handler don't re-parse per call. Replaces the
    /// prior fragile color-comparison approach in both sites (which
    /// depended on the syntax highlighter's background-color tolerance
    /// check and could briefly mis-classify during theme switches).
    func isFragmentRangeInsideCodeBlock(_ range: NSRange) -> Bool {
        guard let codeTokens = cachedParsedDocument?.codeTokens, !codeTokens.isEmpty
        else { return false }
        return MarkdownDetection.isInsideCodeBlock(range: range, codeTokens: codeTokens)
    }

    // MARK: - Redraw-trigger helpers

    /// Compute the ordinal-disambiguated key for a heading line at
    /// `lineRange` in `nsText`. Mirrors the key-computation rule in
    /// `MarkdownDetection.foldableHeadings(...)` (Decision 1 — first
    /// occurrence keeps bare key; Nth identical occurrence gets `[N]`
    /// suffix). Used by the renderer's `headingKey` accessor and the
    /// hover handler's hit-test so both agree on the key shape the
    /// `foldedHeadings` Set + `hoveredHeadingKey` are written/read with.
    ///
    /// O(N) document walk. Called from hover/click hot paths but only
    /// once the cursor is confirmed to be over a heading row, so the
    /// per-mouseMoved cost stays bounded.
    static func disambiguatedHeadingKey(
        forLineRange lineRange: NSRange,
        in nsText: NSString
    ) -> String {
        let bareKey = nsText.substring(with: lineRange)
            .trimmingCharacters(in: .newlines)
        var count = 1
        var location = 0
        while location < lineRange.location {
            let line = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineText = nsText.substring(with: line).trimmingCharacters(in: .newlines)
            if lineText == bareKey { count += 1 }
            let next = line.location + line.length
            if next <= location { break }
            location = next
        }
        return count == 1 ? bareKey : "\(bareKey) [\(count)]"
    }

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
    /// `foldedHeadings` binding. When the set changes, invalidates layout
    /// over the union of old + new ranges so the content-storage delegate
    /// is re-queried and the new fold state is reflected on screen.
    ///
    /// The content-storage delegate (`textContentStorage(_:textParagraphWith:)`,
    /// in this same extension) returns an empty `NSTextParagraph` for any
    /// source range intersecting `foldedRanges`. The layout manager then
    /// vends no fragments for that range — true zero-height collapse,
    /// natural propagation to downstream fragment positions, and folded
    /// content is unreachable to selection/find/spell-check.
    func syncHeadingFolding(in ts: NSTextStorage, textView: NSTextView) {
        // Fast path: no folds requested → guarantee an empty result without
        // walking the AST. Common case for unedited pages.
        if foldedHeadings.isEmpty {
            let oldRanges = foldedRanges
            if !foldedRanges.isEmpty { foldedRanges = [] }
            lastSyncedFoldedHeadings = []
            if !oldRanges.isEmpty {
                invalidateFoldLayout(in: textView, union: oldRanges)
            }
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
        // visible to collapse. `invalidateFoldLayout` skips zero-length
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
            let oldRanges = foldedRanges
            foldedRanges = newRanges
            invalidateFoldLayout(in: textView, union: oldRanges + newRanges)
        }
        lastSyncedFoldedHeadings = foldedHeadings
    }

    /// Compute the NSRange union of `ranges` and invalidate layout over
    /// the resulting NSTextRange. Triggers the content-storage delegate
    /// to be re-queried for those source ranges. Shared by
    /// `applyFoldStateIfChanged` (chevron-click path, via `syncHeadingFolding`)
    /// and `syncHeadingFolding` itself (restyle path, when text edits
    /// shifted heading positions).
    fileprivate func invalidateFoldLayout(in textView: NSTextView, union ranges: [NSRange]) {
        var minLoc = Int.max
        var maxEnd = 0
        for r in ranges where r.length > 0 {
            minLoc = min(minLoc, r.location)
            maxEnd = max(maxEnd, r.location + r.length)
        }
        guard minLoc != Int.max, maxEnd > minLoc,
            let tlm = textView.textLayoutManager,
            let tcs = tlm.textContentManager as? NSTextContentStorage,
            let startLoc = tcs.location(tcs.documentRange.location, offsetBy: minLoc),
            let endLoc = tcs.location(tcs.documentRange.location, offsetBy: maxEnd),
            let textRange = NSTextRange(location: startLoc, end: endLoc)
        else { return }
        tlm.invalidateLayout(for: textRange)
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
    /// accompany a text edit (chevron click) and routes through
    /// `syncHeadingFolding`, which rebuilds `foldedRanges` and calls
    /// `invalidateFoldLayout` when the set changes. The content-storage
    /// delegate re-queries for the affected range and vends empty
    /// paragraphs for the newly-folded entries, real paragraphs for the
    /// newly-unfolded ones. No force-layout chain or attribute writes —
    /// TextKit 2's standard layout pass handles propagation.
    func applyFoldStateIfChanged(in ts: NSTextStorage, textView: NSTextView) {
        guard foldedHeadings != lastSyncedFoldedHeadings else { return }
        syncHeadingFolding(in: ts, textView: textView)

        // Engine-specific overscroll / scroll-clamp recompute. TextKit 2's
        // layout-frame propagation handles the visible region naturally; the
        // engine's bottom-overscroll math (scroll-past-end UX) needs an
        // explicit kick since it derives from `baseContentHeight` rather
        // than directly observing the layout manager.
        if let nativeTV = textView as? NativeTextView,
            let scrollView = textView.enclosingScrollView
        {
            nativeTV.recalcOverscroll(for: scrollView, debugTag: "foldToggle")
            (scrollView as? ClampedScrollView)?.clampToInsets()
        }
    }

}

// MARK: - NSTextContentStorageDelegate (paragraph elision)

extension NativeTextViewCoordinator: NSTextContentStorageDelegate {
    /// Returns an empty `NSTextParagraph` for source ranges that intersect
    /// the current `foldedRanges`. The layout manager then sees zero
    /// content for that range — no fragments created, no layout space,
    /// and selection/find/spell-check route through the content manager
    /// so the elided range is unreachable to all of them.
    ///
    /// Returning `nil` for non-folded ranges hands control back to the
    /// default `NSTextContentStorage` behavior (vend the real paragraph).
    public func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard !foldedRanges.isEmpty else { return nil }
        let intersects = foldedRanges.contains { folded in
            NSIntersectionRange(folded, range).length > 0
        }
        guard intersects else { return nil }
        return NSTextParagraph(attributedString: NSAttributedString(string: ""))
    }
}
