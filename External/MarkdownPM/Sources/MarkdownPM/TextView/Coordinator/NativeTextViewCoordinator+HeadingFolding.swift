//
//  NativeTextViewCoordinator+HeadingFolding.swift
//  MarkdownPM
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
//    2. `MarkdownPMEditor.updateNSView` calls `applyFoldStateIfChanged`
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
        // Block-level guard only. `codeTokens` mixes fenced/indented code blocks
        // (`.codeBlock`) with inline code spans (`.inlineCode`). Only a real code
        // BLOCK disqualifies a line from rendering its block construct (bullet •,
        // heading, HR, blockquote bar, fold chevron). An inline `` `code` `` span
        // is line-internal — a `- foo `bar`` bullet or `# Foo `bar`` heading must
        // still render. Filtering to `.codeBlock` keeps the real code-block guard
        // intact while letting inline code coexist on a block line.
        let blockCodeTokens = codeTokens.filter { $0.kind == .codeBlock }
        guard !blockCodeTokens.isEmpty else { return false }
        return MarkdownDetection.isInsideCodeBlock(range: range, codeTokens: blockCodeTokens)
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
    /// `foldedHeadings` set. When the set changes, invalidates layout over
    /// the union of old + new ranges so the content-manager re-enumerates
    /// elements and our `shouldEnumerate` filter takes effect.
    ///
    /// Elision mechanism: `NSTextContentManagerDelegate.shouldEnumerateTextElement:`
    /// (this same extension) returns `false` for elements whose source range
    /// intersects any `foldedRanges` entry. The layout manager vends no
    /// fragments for skipped elements — true zero-height collapse, natural
    /// propagation to downstream fragment positions, and folded content is
    /// unreachable to selection / find / spell-check by construction.
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
        // Phase 3 — reuse the Document cached in parsedDocument(for:)
        // instead of re-parsing here. This is the ONLY remaining Apple
        // parse on the folded-edit hot path; folded pages no longer
        // double-parse (tokens + AST) per keystroke. The fast-path above
        // already guarantees we never reach here when no folds are active.
        // Phase 3.5 — bind the cached spine once and call the prebuilt-index
        // overload so the line index is reused too, not rebuilt here.
        let cached = parsedDocument(for: text)
        let headings = MarkdownDetection.foldableHeadings(
            in: cached.appleDocument,
            nsText: nsText,
            lineIndex: cached.lineIndex
        )

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
            // Move caret out of any newly-folded range BEFORE invalidating.
            // The layout manager refuses to elide elements containing the
            // active selection point — without this, folding a section the
            // caret is sitting inside takes no visual effect until the user
            // moves their cursor elsewhere.
            moveSelectionOutOfFoldedRanges(textView)
            invalidateFoldLayout(in: textView, union: oldRanges + newRanges)
        } else {
        }
        lastSyncedFoldedHeadings = foldedHeadings
    }

    /// If the text view's current selection's leading edge sits inside any
    /// of the current `foldedRanges`, collapse the selection to the position
    /// just before that range starts (end of the heading line above).
    /// Called from `syncHeadingFolding` right before `invalidateFoldLayout`
    /// so the layout pass that follows sees no active selection inside the
    /// to-be-elided content.
    fileprivate func moveSelectionOutOfFoldedRanges(_ textView: NSTextView) {
        guard !foldedRanges.isEmpty else { return }
        let sel = textView.selectedRange()
        let selStart = sel.location
        for folded in foldedRanges {
            if selStart >= folded.location, selStart < folded.location + folded.length {
                let safeLocation = max(0, folded.location - 1)
                textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
                return
            }
        }
    }

    /// Invalidate layout from the earliest affected fold position through
    /// the end of the document, then force the layout cascade to run
    /// immediately. Shared by `applyFoldStateIfChanged` (chevron-click path,
    /// via `syncHeadingFolding`) and `syncHeadingFolding` itself (restyle
    /// path, when text edits shifted heading positions).
    ///
    /// Why fold-start-through-document-end (not just the fold range): when
    /// content shrinks (folding) every fragment BELOW the fold needs to
    /// reposition upward. `invalidateLayout(for:)` only invalidates the
    /// fragments INSIDE its range; fragments after the range keep their
    /// cached Y positions. Without invalidating to document-end, folding
    /// produces zero visible effect because the layout below the fold
    /// stays where it was, leaving a hole that the folded content used to
    /// fill (but visually the hole appears NOT to close — content stays
    /// "visible" via the cached fragments).
    ///
    /// The four-step sequence: invalidate stale layout, ensureLayout to
    /// force immediate re-iteration via `enumerateTextElements` (where our
    /// `shouldEnumerate` delegate filters folded elements), viewport
    /// layout controller to re-tile visible fragments, and `needsDisplay`
    /// to schedule the AppKit redraw.
    fileprivate func invalidateFoldLayout(in textView: NSTextView, union ranges: [NSRange]) {
        var minLoc = Int.max
        for r in ranges where r.length > 0 {
            minLoc = min(minLoc, r.location)
        }
        guard minLoc != Int.max,
            let tlm = textView.textLayoutManager,
            let tcs = tlm.textContentManager as? NSTextContentStorage,
            let startLoc = tcs.location(tcs.documentRange.location, offsetBy: minLoc),
            let textRange = NSTextRange(
                location: startLoc, end: tcs.documentRange.endLocation)
        else {
            return
        }

        tlm.invalidateLayout(for: textRange)
        tlm.ensureLayout(for: textRange)

        // Force the hit-test layout discovery that super.mouseDown would
        // normally trigger. Without this, our chevron-click path short-
        // circuits NSTextView's internal layout cascade (super.mouseDown is
        // skipped to prevent the caret from jumping to the click point), and
        // `shouldEnumerate` only gets consulted on unrelated subsequent
        // events. `textLayoutFragment(for:)` is the same call NSTextView's
        // mouseDown makes internally to find which fragment the click landed
        // in — and the side effect of that lookup is the full element
        // re-iteration we need.
        _ = tlm.textLayoutFragment(for: startLoc)

        tlm.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
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

    /// Drop first-responder status when the current selection's leading
    /// edge lies inside any `foldedRanges` entry. Decision 2: chevron
    /// click preserves caret + selection by default; this helper only
    /// fires when the post-toggle caret would otherwise vanish inside an
    /// elided range with no fragment to render it. Used from the click
    /// handler in `NativeTextView+HeadingFoldHover`.
    @discardableResult
    func unfocusCaretIfInsideFoldedRange(_ textView: NSTextView) -> Bool {
        guard !foldedRanges.isEmpty else { return false }
        let sel = textView.selectedRange()
        let selStart = sel.location
        for folded in foldedRanges {
            if selStart >= folded.location, selStart < folded.location + folded.length {
                textView.window?.makeFirstResponder(nil)
                return true
            }
        }
        return false
    }

    /// Fold-toggle entry: detects a `foldedHeadings` change that didn't
    /// accompany a text edit (chevron click) and routes through
    /// `syncHeadingFolding`, which rebuilds `foldedRanges` and calls
    /// `invalidateFoldLayout` when the set changes. The content-storage
    /// delegate re-queries for the affected range and vends empty
    /// paragraphs for the newly-folded entries, real paragraphs for the
    /// newly-unfolded ones. No force-layout chain or attribute writes —
    /// TextKit 2's standard layout pass handles propagation.
    func applyFoldStateIfChanged(in ts: NSTextStorage, textView: NSTextView) {
        guard foldedHeadings != lastSyncedFoldedHeadings else {
            return
        }
        syncHeadingFolding(in: ts, textView: textView)

        // The layout pass `syncHeadingFolding` just ran will silently
        // override `shouldEnumerate == false` for the one element that
        // currently hosts the caret — AppKit force-lays it out so the
        // caret has a fragment to render in. Result: the fold appears to
        // not take effect when the user clicked the chevron while their
        // caret was inside the section being folded. Once the caret moves
        // out (a manual click elsewhere, or any natural layout pass),
        // the elision finally takes hold.
        //
        // Fix: if the post-toggle caret would land inside an elided
        // range, drop first-responder AND re-invalidate over the current
        // fold ranges. The second pass runs with no selection anchoring
        // inside the elided region, so `shouldEnumerate == false` is
        // honored cleanly. Cheap — the second invalidate only does work
        // when an unfocus actually happened.
        if unfocusCaretIfInsideFoldedRange(textView), !foldedRanges.isEmpty {
            invalidateFoldLayout(in: textView, union: foldedRanges)
        }

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

// MARK: - NSTextContentStorageDelegate / NSTextContentManagerDelegate
//
// Content-layer elision for folded ranges. Apple's `NSTextContentManager.h`
// documents two relevant primitives:
//
//   1. `textContentStorage:textParagraphWithRange:` — paragraph *substitution*.
//      The returned paragraph's attributedString MUST have `range.length`
//      (header line 120). We do NOT use this for folding — empty-paragraph
//      substitution crashes `enumerateTextElementsFromLocation:` in
//      `setParagraphSeparatorRange:` because the content storage indexes
//      characters by the source range while the substituted paragraph has
//      zero length. We return nil from this method (default behavior).
//
//   2. `textContentManager:shouldEnumerateTextElement:options:` — element
//      *omission*. Returning false skips the element from layout enumeration
//      (header line 40 + 112-113: "it can skip a range… or hide some elements
//      from the layout. Returning NO indicates textElement to be skipped from
//      the enumeration"). The layout manager never sees skipped elements:
//      zero space allocated, no fragments constructed, no draw — and
//      selection / find / spell-check naturally route through the same
//      enumeration, so folded content is unreachable to them too.
//
// `NSTextContentStorageDelegate` inherits from `NSTextContentManagerDelegate`
// (header line 118), so our existing single conformance declaration carries
// both protocols. We implement (2) for actual folding and leave (1) as a
// no-op nil-return.

extension NativeTextViewCoordinator: NSTextContentStorageDelegate {
    /// Element-level omission for folded ranges. Apple's documented
    /// mechanism for "hide some elements from the layout."
    ///
    /// Skipped elements are invisible to the layout manager (no fragment
    /// construction, no vertical space) AND to the selection / find /
    /// spell-check paths, which iterate through the same enumeration.
    /// Folded content becomes naturally unreachable — no caret-skip
    /// patches needed.
    ///
    /// Headings themselves are NEVER in `foldedRanges` (fold range starts
    /// at the end of the heading line and ends at the start of the next
    /// equal-or-higher heading), so the heading row stays enumerated and
    /// the chevron + heading text continue to render normally.
    public func textContentManager(
        _ textContentManager: NSTextContentManager,
        shouldEnumerate textElement: NSTextElement,
        options: NSTextContentManager.EnumerationOptions = []
    ) -> Bool {
        guard !foldedRanges.isEmpty else {
            return true
        }
        guard let elementTextRange = textElement.elementRange else {
            return true
        }
        let documentLocation = textContentManager.documentRange.location
        let startOffset = textContentManager.offset(
            from: documentLocation, to: elementTextRange.location)
        let endOffset = textContentManager.offset(
            from: documentLocation, to: elementTextRange.endLocation)
        guard startOffset != NSNotFound, endOffset != NSNotFound,
            endOffset >= startOffset
        else {
            return true
        }
        let elementNSRange = NSRange(location: startOffset, length: endOffset - startOffset)
        for folded in foldedRanges {
            if NSIntersectionRange(folded, elementNSRange).length > 0 {
                return false
            }
        }
        return true
    }

    /// Kept as a no-op. The paragraph-substitution contract requires the
    /// returned paragraph's attributedString to match `range.length` exactly
    /// (header line 120); returning an empty paragraph for a non-empty
    /// range crashes the storage. All folding goes through
    /// `shouldEnumerate` above.
    public func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        return nil
    }
}
