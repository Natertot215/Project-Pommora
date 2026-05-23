### Foldable Headings Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the failed `layoutFragmentFrame`-override + attribute-write fold mechanism with content-manager elision (`NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)`), preserving all chevron visuals/interaction while gaining true zero-height collapse, unreachable folded content, and clean caret/selection/find behavior.

**Architecture:** Strip the broken collapse layer + every patch around it (caret-skip, `isInsideFoldedRange` guards, layout-force chain, attribute writes). Extract L2-shared helpers (chevron-geometry, fragment-NSRange, AST-based code-block detection) that the renderer and hover handler currently duplicate. Rebuild fold collapse around `NSTextContentStorageDelegate` returning empty `NSTextParagraph` for ranges intersecting `coordinator.foldedRanges`. Add ordinal disambiguation on heading keys (Decision 1), conditional unfocus on chevron click (Decision 2), and orphan-key reconciliation on save.

**Tech Stack:** Swift 6 strict concurrency + AppKit + TextKit 2 (`NSTextContentStorage` / `NSTextContentStorageDelegate` / `NSTextLayoutManager` / `NSTextLayoutFragment`) + Apple swift-markdown + vendored swift-markdown-engine + Yams (frontmatter persistence). Build via `xcodebuild`; test via `xcodebuild test -only-testing:PommoraTests/<FilenameWithTests>` (quirk #1).

---

#### Locked decisions

- **Decision 1 — Ordinal disambiguation for heading keys.** First occurrence of `## Foo` keys as `"## Foo"`; subsequent identical-text headings get `"## Foo [2]"`, `"## Foo [3]"`, etc. Solves duplicate-heading collision; rename behavior unchanged (rename drops state, then orphan reconciliation cleans the stale key on save).
- **Decision 2 — Conditional unfocus on chevron click.** `window?.makeFirstResponder(nil)` runs ONLY when the caret would otherwise land inside the freshly-folded range. In all other cases, caret stays put — chevron clicks don't interrupt active editing.

---

#### File structure

##### Modified (engine)

- [`External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift) — add ordinal `[N]` disambiguation to `foldableHeadings(...)`'s key computation.
- [`External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) — strip `isInsideFoldedRange` + its guards in `renderingSurfaceBounds` + `draw(at:in:)`; replace local `chevronRect(at:)` with call to shared `HeadingChevronGeometry`; replace local `hasCodeBlockBackground` with call to shared AST-based check; mirror ordinal key computation in `headingKey`.
- [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift) — remove `isPushingCaretOutOfFold` flag.
- [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift) — strip `foldHideParagraphStyle`, `foldHideFont`, `applyFoldHideAttributes`; strip `skipCaretOutOfFoldedRangesIfNeeded`; rebuild `syncHeadingFolding` to call `invalidateLayout(for:)` instead of writing attributes; rebuild `applyFoldStateIfChanged` to single invalidate-and-overscroll-touch-up; add `NSTextContentStorageDelegate` conformance extension; restore `unfocusCaretIfInsideFoldedRange` with cleaner conditional.
- [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift) — remove `skipCaretOutOfFoldedRangesIfNeeded` call at top of `textViewDidChangeSelection`.
- [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift) — convert tracking area to single-create on view setup; unify hit-test into one helper consumed by hover + cursor + click sites; replace local `chevronViewRect(for:)` with shared `HeadingChevronGeometry`; replace local `fragmentNSRange(for:)` with shared extension; replace local `headingFragmentInsideCodeBlock` with shared AST-based check; rewrite the `makeFirstResponder(nil)` comment to reflect Decision-2 UX (no layout-pump rationale).
- [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextViewWrapper.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextViewWrapper.swift) — wire `textContentStorage.delegate = coordinator` in `makeNSView` before the first layout pass.

##### Modified (Pommora)

- [`Pommora/Pommora/Pages/PageEditorViewModel.swift`](Pommora/Pommora/Pages/PageEditorViewModel.swift) — add `reconcileFoldedHeadings()` helper called from `flushNow()` before save; drops orphan keys whose heading text no longer exists in the body.

##### New (engine)

- `External/MarkdownEngine/Sources/MarkdownEngine/Util/HeadingChevronGeometry.swift` — single static struct exposing chevron-rect computation in both fragment-local and view coordinates.
- `External/MarkdownEngine/Sources/MarkdownEngine/Util/NSTextLayoutFragment+NSRange.swift` — `var nsRange: NSRange?` extension reading from the fragment's `textContentManager` chain.

##### Modified docs

- [`External/MarkdownEngine/NOTICE.md`](External/MarkdownEngine/NOTICE.md) — rewrite the v0.2.x foldable-headings entries to reflect content-manager elision architecture.
- [`.claude/Guidelines/Markdown.md`](.claude/Guidelines/Markdown.md) — rewrite §9.11 to drop the WIP banner and describe the shipped content-manager-elision architecture; remove the non-existent `isSyncingHeadingFolds` reference (line 488).
- [`.claude/Features/PageEditor.md`](.claude/Features/PageEditor.md) — promote line 141 from WIP back to SHIPPED with the new architecture summary.
- [`.claude/Features/Pages.md`](.claude/Features/Pages.md) — promote line 33 from WIP back to a shipped-feature description.
- Nexus mirrors of all four docs at `/Users/nathantaichman/The Nexus/Pages/Pommora/...`.

##### Tests touched

- [`Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift`](Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift) — add tests for ordinal disambiguation: two duplicates → `[2]` suffix; three duplicates → `[2]` + `[3]`; non-adjacent duplicates; rename-then-orphan key gone after reconciliation.

---

#### Phase 1: Strip the broken collapse mechanism + its patches

Each task ships green standalone. After this phase, the codebase compiles and chevrons still draw/hover/click correctly; fold toggling becomes a no-op (state changes but nothing visually collapses). This intermediate state is acceptable — Phase 3 reinstates collapse via the new primitive.

##### Task 1.1: Remove `foldHideParagraphStyle`, `foldHideFont`, `applyFoldHideAttributes`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift:151-189`

- [ ] **Step 1: Delete the three static members and the function**

Delete lines 151-189 in their entirety:
```swift
// MARK: - Fold-hide attribute writes

nonisolated(unsafe) private static let foldHideParagraphStyle: NSParagraphStyle = { ... }()
nonisolated(unsafe) private static let foldHideFont: NSFont = NSFont.systemFont(ofSize: 0.01)

static func applyFoldHideAttributes(in ts: NSTextStorage, ranges: [NSRange]) { ... }
```

Remove the `// MARK: - Fold-hide attribute writes` comment line too.

- [ ] **Step 2: Remove the call site in `syncHeadingFolding`**

In the same file, find the call near the end of `syncHeadingFolding(in:textView:)` (line 142):
```swift
        Self.applyFoldHideAttributes(in: ts, ranges: foldedRanges)
```
Delete it, plus the preceding 7-line comment block (lines 137-141 starting with `// Apply fold-hide attributes...`).

- [ ] **Step 3: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. Folded ranges still compute (the renderer's `isInsideFoldedRange` guard is stripped in Task 1.5, after which collapse becomes a no-op visually — that's expected).

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift
git commit -m "refactor(editor): strip attribute-write fold-hide mechanism"
```

---

##### Task 1.2: Strip `applyFoldStateIfChanged`'s layout-force chain + restyle-of-unfolded loop

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift:337-422`

- [ ] **Step 1: Replace `applyFoldStateIfChanged` body with a minimal stub**

Replace the entire function body (lines 337-422) with this temporary stub:
```swift
    func applyFoldStateIfChanged(in ts: NSTextStorage, textView: NSTextView) {
        guard foldedHeadings != lastSyncedFoldedHeadings else { return }
        // Phase-1 stub: state diff only; Phase-3 reinstates layout invalidation
        // via content-manager elision. Until then, toggling a chevron updates
        // bookkeeping but produces no visible collapse.
        syncHeadingFolding(in: ts, textView: textView)
    }
```

Keep the preceding doc comment block but trim it to one sentence: `/// Fold-toggle entry: detects a `foldedHeadings` change that didn't accompany a text edit (chevron click) and re-runs the AST walk. Layout invalidation arrives in Phase 3.`

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift
git commit -m "refactor(editor): stub applyFoldStateIfChanged pending Phase 3 rebuild"
```

---

##### Task 1.3: Strip `skipCaretOutOfFoldedRangesIfNeeded` + `unfocusCaretIfInsideFoldedRange` + `isPushingCaretOutOfFold`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift:424-508`
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift:124-128`

- [ ] **Step 1: Delete both functions + the MARK comment**

In `+HeadingFolding.swift`, delete lines 424-508 (the `// MARK: - Caret skip across folded ranges` section plus both functions). They get reinstated in Phase 4 with a cleaner shape.

- [ ] **Step 2: Delete `isPushingCaretOutOfFold` flag from coordinator**

In `NativeTextViewCoordinator.swift`, delete lines 124-128 (the doc comment + the `var isPushingCaretOutOfFold: Bool = false` declaration).

- [ ] **Step 3: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **` — the call site in `+TextDelegate.swift` still references `skipCaretOutOfFoldedRangesIfNeeded` and will fail to compile. Confirm the error is exactly: `'NativeTextViewCoordinator' has no member 'skipCaretOutOfFoldedRangesIfNeeded'`. Proceed to Task 1.4 to remove the call site.

- [ ] **Step 4: Do NOT commit yet** — wait for Task 1.4 to restore green build.

---

##### Task 1.4: Remove caret-skip call in `+TextDelegate.swift`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift:169-175`

- [ ] **Step 1: Delete the call + its 7-line comment**

Replace lines 169-175:
```swift
        // Caret-skip across folded ranges. If the new selection lands inside
        // (or spans into) a folded heading's content, push it past the fold
        // first — `setSelectedRange` re-fires this delegate method, and the
        // recursive call sees the corrected selection. Short-circuit the
        // outer call so downstream logic doesn't run against the stale
        // pre-skip selection.
        if skipCaretOutOfFoldedRangesIfNeeded(tv) { return }
```

With a single blank line. The content-manager elision in Phase 3 makes folded ranges unreachable to selection in the first place — no skip needed.

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit (covers Tasks 1.3 + 1.4)**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift
git commit -m "refactor(editor): strip caret-skip patch pending content-elision rebuild"
```

---

##### Task 1.5: Strip `isInsideFoldedRange` + its two guards in the renderer

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift:113-130` (helper)
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift:721-727` (renderingSurfaceBounds early-return)
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift:813-820` (draw early-return)

- [ ] **Step 1: Delete the `isInsideFoldedRange` computed property**

Delete lines 113-130 (the doc comment + the property definition). Also delete the preceding empty `MARK: - Foldable headings` section line if no other helpers remain immediately above (the heading helpers below stay).

- [ ] **Step 2: Delete the guard in `renderingSurfaceBounds`**

Find the lines (around 723-726):
```swift
            // Folded fragments report zero rendering bounds so TextKit doesn't
            // try to draw overlays (HR line, blockquote chrome, etc.) into a
            // visually-collapsed surface.
            if isInsideFoldedRange { return .zero }
```
Delete all four lines.

- [ ] **Step 3: Delete the guard in `draw(at:in:)`**

Find the lines (around 815-820):
```swift
            // Foldable headings — skip every overlay + `super.draw` when
            // this fragment lives inside a folded section. The frame is
            // already zero-height; bailing here avoids running the overlay
            // detection passes (HR / blockquote / bullet / task) on each
            // hidden fragment per draw.
            if isInsideFoldedRange { return }
```
Delete all six lines.

- [ ] **Step 4: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. After this commit, clicking a chevron updates `foldedHeadings` state but produces no visible collapse — that's intentional; Phase 3 reinstates collapse via content elision.

- [ ] **Step 5: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift
git commit -m "refactor(editor): strip isInsideFoldedRange renderer guards"
```

---

##### Task 1.6: Rewrite the `makeFirstResponder(nil)` comment (keep the call for now)

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift:269-277`

- [ ] **Step 1: Replace the 7-line comment + call with a placeholder comment + same call**

Replace lines 269-277:
```swift
        // Chevron click is a button-style action: remove the caret /
        // selection from the page entirely. macOS-native way to make the
        // caret visually disappear is to resign first responder — there's
        // no public API to hide the insertion point while keeping focus.
        // The side effect (responder change) also pumps AppKit's redisplay
        // path, which reliably propagates the fold layout collapse to the
        // screen regardless of where the caret was before the click.
        window?.makeFirstResponder(nil)
```

With:
```swift
        // Phase-4 will replace this with conditional unfocus (Decision 2):
        // unconditional resignation here is a temporary stand-in so Phase 1
        // ships green. Final shape: only drop focus when the post-toggle
        // caret would otherwise land inside the freshly-folded range.
        window?.makeFirstResponder(nil)
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "refactor(editor): mark chevron-click unfocus as temporary stand-in"
```

---

#### Phase 2: Extract shared helpers (L2 cleanup)

L2 in Markdown.md guidelines: renderer and service MUST share detection logic. Phase 2 fixes three duplications (chevron-rect math, fragment-NSRange, code-block detection) that were shipped as parallel implementations.

##### Task 2.1: Create `HeadingChevronGeometry` shared helper

**Files:**
- Create: `External/MarkdownEngine/Sources/MarkdownEngine/Util/HeadingChevronGeometry.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  HeadingChevronGeometry.swift
//  MarkdownEngine
//
//  Shared rect computation for the foldable-headings chevron. Renderer
//  (`MarkdownTextLayoutFragment.drawHeadingChevron`) and hover handler
//  (`NativeTextView+HeadingFoldHover`) consume the SAME math so the visible
//  glyph and the click hit-test agree by construction (Markdown.md L2).
//

import AppKit

enum HeadingChevronGeometry {
    /// Visual constants. Match the prior local implementations.
    static let glyphSize: CGFloat = 12
    static let textGap: CGFloat = 6

    /// Chevron rect for a fragment whose origin is `fragmentOrigin` and whose
    /// first line fragment has typographic bounds `firstLineBounds`.
    /// `fragmentOrigin` is in the coordinate space the caller wants the rect
    /// expressed in (view coords for hover; fragment-local coords for the
    /// renderer's draw call). `containerLeading` is the text container's
    /// leading edge in the same coordinate space.
    static func rect(
        fragmentOrigin: CGPoint,
        containerLeading: CGFloat,
        firstLineBounds: CGRect
    ) -> CGRect {
        let gutterX = containerLeading - glyphSize - textGap
        let midY = fragmentOrigin.y + firstLineBounds.midY
        return CGRect(
            x: gutterX,
            y: midY - glyphSize / 2,
            width: glyphSize,
            height: glyphSize
        )
    }
}
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **` (file is new + unreferenced; PBXFileSystemSynchronizedRootGroup auto-includes per quirk #2).

- [ ] **Step 3: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Util/HeadingChevronGeometry.swift
git commit -m "feat(editor): add HeadingChevronGeometry shared helper"
```

---

##### Task 2.2: Refactor renderer to use `HeadingChevronGeometry`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift:186-227`

- [ ] **Step 1: Replace `chevronRect(at:)` body to call the shared helper**

Replace the function body (currently lines 209-227) with:
```swift
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
```

Keep the existing doc comment above the function (lines 186-208) — its explanation of fragment-local vs view-coord call sites is still accurate.

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Visual sanity check via manual run**

Run the app (`xcodebuild -scheme Pommora -destination 'platform=macOS' build` then launch from Xcode or `open` the built app). Hover a heading line. Chevron should appear in the same position as before. If shifted, the call-site coordinate translation is wrong — revisit `containerLeading` math.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift
git commit -m "refactor(editor): renderer consumes HeadingChevronGeometry"
```

---

##### Task 2.3: Refactor hover handler to use `HeadingChevronGeometry`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift:280-305`

- [ ] **Step 1: Replace `chevronViewRect(for:)` body**

Replace the function (lines 280-305) with:
```swift
    private func chevronViewRect(for fragment: NSTextLayoutFragment) -> CGRect? {
        guard textLayoutManager?.textContainer != nil,
            let firstLine = fragment.textLineFragments.first
        else { return nil }
        // Translate fragment origin into view coords. The renderer's call site
        // uses fragment-local origin; this site uses view-coord origin.
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
```

The 10-line doc comment above (lines 280-283) stays accurate; trim it to one sentence: `/// Chevron rect in VIEW coordinates for a layout fragment. Mirrors the renderer's `chevronRect(at:)` via shared `HeadingChevronGeometry` (L2).`

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Click hit-test sanity check**

Run the app. Hover a heading; chevron appears. Click the chevron — fold state should still toggle (visually no collapse yet; Phase 3 lands that). Hit-test offsets unchanged from prior behavior.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "refactor(editor): hover handler consumes HeadingChevronGeometry"
```

---

##### Task 2.4: Create `NSTextLayoutFragment+NSRange` extension

**Files:**
- Create: `External/MarkdownEngine/Sources/MarkdownEngine/Util/NSTextLayoutFragment+NSRange.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  NSTextLayoutFragment+NSRange.swift
//  MarkdownEngine
//
//  Shared helper for converting a fragment's `rangeInElement` into a
//  document-relative `NSRange`. Both the renderer
//  (`MarkdownTextLayoutFragment`) and the hover handler
//  (`NativeTextView+HeadingFoldHover`) need this; previously each shipped its
//  own implementation (L2 violation). The extension reads via the standard
//  `textContentManager → NSTextContentStorage` chain.
//

import AppKit

extension NSTextLayoutFragment {
    /// Document-relative NSRange for this fragment's content, or `nil` if the
    /// content manager isn't an `NSTextContentStorage` (atypical) or the range
    /// doesn't resolve.
    var nsRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage
        else { return nil }
        let docStart = tcs.documentRange.location
        let start = tcs.offset(from: docStart, to: rangeInElement.location)
        let end = tcs.offset(from: docStart, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
```

- [ ] **Step 2: Refactor renderer call site**

In `MarkdownTextLayoutFragment.swift`, delete the local `fragmentNSRange` computed property (lines 856-864). Inside the same file, the references to `fragmentNSRange` become `nsRange` (Swift resolves the extension property on `self` because `MarkdownTextLayoutFragment: NSTextLayoutFragment`).

Find-replace inside that file: `fragmentNSRange` → `nsRange`. Verify each instance — should be ~12 hits.

- [ ] **Step 3: Refactor hover handler call site**

In `NativeTextView+HeadingFoldHover.swift`, delete the local `fragmentNSRange(for:)` function (lines 173-186). Replace its callers:
```swift
fragmentNSRange(for: fragment)
```
becomes:
```swift
fragment.nsRange
```
Two hits in the file.

- [ ] **Step 4: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Util/NSTextLayoutFragment+NSRange.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "refactor(editor): extract NSTextLayoutFragment.nsRange shared extension"
```

---

##### Task 2.5: Replace fragile color-comparison code-block checks with AST-based detection

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift` (multiple sites)
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift:192-209`

- [ ] **Step 1: Add a fragment-level convenience on the coordinator**

In `+HeadingFolding.swift`, add this helper near the top of the existing extension block:
```swift
    /// AST-grounded code-block check for a fragment at `range`. Uses the
    /// coordinator's already-cached `cachedParsedDocument.codeTokens` so
    /// the renderer and hover handler don't re-parse per call. Replaces
    /// the prior fragile color-comparison approach (which depended on the
    /// syntax highlighter's background-color tolerance check and could
    /// briefly mis-classify during theme switches).
    func isFragmentRangeInsideCodeBlock(_ range: NSRange) -> Bool {
        guard let codeTokens = cachedParsedDocument?.codeTokens, !codeTokens.isEmpty
        else { return false }
        return MarkdownDetection.isInsideCodeBlock(range: range, codeTokens: codeTokens)
    }
```

- [ ] **Step 2: Replace renderer's `hasCodeBlockBackground`**

Two important nuances: (a) `hasCodeBlockBackground` in the renderer is also used by `drawCodeBlockBackground` itself to decide whether to draw the bg — that use case still needs the color check (it's literally asking "does this fragment have the code-block bg styling already"). Only the call sites that use it as a "is this inside a code block" proxy need to migrate to AST-based.

Audit call sites:
- `hasThematicBreak` (line 71-78) — uses for stage-0 guard. Should migrate to AST.
- `hasDashBulletMarker` (line 330-337) — uses for stage-0 guard. Should migrate to AST.
- `hasBlockquoteMarker` (line 421-449) — uses for stage-0 guard. Should migrate to AST.
- `hasHeadingMarker` (line 147-152) — uses for stage-0 guard. Should migrate to AST.
- `drawCodeBlockBackground` (line 923-977) — uses for "is this the styling I should draw?" Stays as color check.

For each of the four detection helpers, replace `hasCodeBlockBackground` with `isInsideCodeBlockAST` (a new helper inside `MarkdownTextLayoutFragment`):

```swift
    @MainActor
    private var isInsideCodeBlockAST: Bool {
        guard let range = nsRange,
            let coordinator = nearestCoordinator()
        else { return false }
        return coordinator.isFragmentRangeInsideCodeBlock(range)
    }
```

Add this helper near the other heading helpers. Then in the four stage-0 guards, replace `hasCodeBlockBackground` with `isInsideCodeBlockAST`.

- [ ] **Step 3: Replace hover handler's `headingFragmentInsideCodeBlock`**

In `NativeTextView+HeadingFoldHover.swift`, delete the function (lines 192-209) plus its 4-line doc comment. Replace the two call sites:
```swift
let insideCodeBlock = headingFragmentInsideCodeBlock(textStorage: textStorage, range: nsRange)
```
becomes:
```swift
let insideCodeBlock = (delegate as? NativeTextViewCoordinator)?
    .isFragmentRangeInsideCodeBlock(nsRange) ?? false
```

- [ ] **Step 4: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Test verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora test -destination 'platform=macOS' -only-testing:PommoraTests/FoldableHeadingsTests`
Expected: `** TEST SUCCEEDED **` with 13 tests. The "Heading inside fenced code block is NOT foldable" test (line 135) confirms code-block guard still works AST-side.

- [ ] **Step 6: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "refactor(editor): AST-based code-block check replaces color comparison"
```

---

#### Phase 3: Content-manager elision rebuild

This is the core of the rebuild. After this phase, clicking a chevron actually collapses the section to zero height via TextKit 2's canonical primitive.

##### Task 3.1: Add `NSTextContentStorageDelegate` conformance + `textContentStorage(_:textParagraphWith:)`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift`

- [ ] **Step 1: Add the delegate conformance extension**

Append to the end of `+HeadingFolding.swift`:
```swift
// MARK: - NSTextContentStorageDelegate (paragraph elision)

extension NativeTextViewCoordinator: NSTextContentStorageDelegate {
    /// Returns an empty `NSTextParagraph` for source ranges that intersect
    /// the current `foldedRanges`. The layout manager then sees no content
    /// for that range — no fragments are created, no layout space is
    /// occupied, and selection/find/spell-check route through the content
    /// manager so the elided range is unreachable.
    ///
    /// Returning `nil` for non-folded ranges hands control back to the
    /// default `NSTextContentStorage` behavior.
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
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. The delegate method exists but isn't wired yet — Task 3.2 wires it.

- [ ] **Step 3: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift
git commit -m "feat(editor): add NSTextContentStorageDelegate conformance for paragraph elision"
```

---

##### Task 3.2: Wire `textContentStorage.delegate = coordinator` before first layout

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextViewWrapper.swift` (in `makeNSView`)

- [ ] **Step 1: Read the relevant slice of `makeNSView`**

First read `NativeTextViewWrapper.swift` lines 100-280 to locate the exact spot where `textContentStorage` is constructed/accessed during view setup. The pattern is typically: NSScrollView → NSTextView (NativeTextView) → textContainer → textLayoutManager → textContentManager (the NSTextContentStorage).

- [ ] **Step 2: Insert the delegate-wire call**

After the NSTextView is fully constructed (its textContentStorage exists) AND before the first call to `rebuildTextStorageAndStyle` or any layout-forcing call, insert:
```swift
// Foldable headings: wire the content-storage delegate so the initial
// layout pass already honors `folded_headings` from frontmatter — no
// flash of expanded content on cold-open of a page with folds.
if let tcs = textView.textLayoutManager?.textContentManager as? NSTextContentStorage {
    tcs.delegate = context.coordinator
}
```

Exact insertion location: find the first `rebuildTextStorageAndStyle` call in `makeNSView` and place the delegate-wire 1-2 lines above it. If `makeNSView` doesn't call rebuild and that happens in `updateNSView` only, place the delegate-wire at the end of `makeNSView` after all NSTextView property setup.

- [ ] **Step 3: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test**

Run the app. Open a `.md` file with frontmatter `folded_headings: ["## Some Section"]` and a `## Some Section` heading + content. Expected: page opens with that section already collapsed (zero height). If the section briefly appears expanded then collapses, the delegate-wire is happening AFTER first layout — move it earlier.

- [ ] **Step 5: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextViewWrapper.swift
git commit -m "feat(editor): wire content-storage delegate before first layout"
```

---

##### Task 3.3: Rebuild `applyFoldStateIfChanged` with a single `invalidateLayout` call

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift` (the stub from Task 1.2)

- [ ] **Step 1: Replace the Task 1.2 stub with the final implementation**

```swift
    /// Fold-toggle entry: detects a `foldedHeadings` change that didn't
    /// accompany a text edit (chevron click), recomputes `foldedRanges`, and
    /// invalidates layout over the affected range so the content-storage
    /// delegate is re-queried. The delegate vends empty paragraphs for the
    /// newly-folded ranges (collapse) or default paragraphs for the newly-
    /// unfolded ones (expand). TextKit 2's standard layout pass propagates
    /// the height change to subsequent fragments — no force-layout chain
    /// needed.
    func applyFoldStateIfChanged(in ts: NSTextStorage, textView: NSTextView) {
        guard foldedHeadings != lastSyncedFoldedHeadings else { return }

        let oldRanges = foldedRanges
        syncHeadingFolding(in: ts, textView: textView)
        let newRanges = foldedRanges

        // Compute the union of old + new ranges → the layout window that
        // needs re-querying. Both arrays are NSRange values into the same
        // textStorage.
        var minLoc = Int.max
        var maxEnd = 0
        for r in oldRanges + newRanges where r.length > 0 {
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

        // Engine-specific overscroll/scroll-clamp recompute. Standard
        // TextKit 2 frame propagation handles the visible region; the
        // overscroll math (bottom padding for the scroll-past-end UX)
        // needs an explicit kick.
        if let nativeTV = textView as? NativeTextView,
            let scrollView = textView.enclosingScrollView
        {
            nativeTV.recalcOverscroll(for: scrollView, debugTag: "foldToggle")
            (scrollView as? ClampedScrollView)?.clampToInsets()
        }
    }
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual fold/unfold test**

Run the app. Open a page with no folds. Hover a heading; click the chevron. Expected: the section under the heading collapses to zero height; subsequent content moves up. Click the chevron again. Expected: the section expands back to its original height.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift
git commit -m "feat(editor): rebuild applyFoldStateIfChanged around content-elision invalidation"
```

---

##### Task 3.4: Add `invalidateLayout` call to `syncHeadingFolding` for restyle path

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift`

- [ ] **Step 1: Augment `syncHeadingFolding` to invalidate on change**

After the existing line where `foldedRanges` is updated (`foldedRanges = newRanges` around line 133), add the invalidate-layout call so restyle-driven changes also trigger collapse:

```swift
        if !unchanged {
            let oldRanges = foldedRanges
            foldedRanges = newRanges
            // Restyle path: text edits may have shifted heading positions
            // (added / removed / reordered). Invalidate the affected window
            // so the delegate is re-queried for the new ranges.
            invalidateFoldLayout(
                in: textView,
                union: oldRanges + newRanges
            )
        }
```

Add the helper near the top of the file (replaces the previous direct call):
```swift
    /// Compute the NSRange union of `ranges` and invalidate layout over
    /// the resulting NSTextRange. Shared by `applyFoldStateIfChanged` and
    /// `syncHeadingFolding` (restyle path).
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
```

Also refactor `applyFoldStateIfChanged` (from Task 3.3) to use the same helper — replace its inline union-and-invalidate block with `invalidateFoldLayout(in: textView, union: oldRanges + newRanges)`.

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Test verification — text edits inside a folded section**

Run the app. Open a page with two H2 sections; fold the first. Edit text inside the SECOND section (which is unfolded). Expected: the first section stays folded; no flicker, no flash. Edits inside an unfolded section don't affect fold state of unrelated sections.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift
git commit -m "refactor(editor): share invalidateFoldLayout between toggle and restyle paths"
```

---

#### Phase 4: Locked decisions — ordinal disambiguation + conditional unfocus

##### Task 4.1: Add ordinal disambiguation to `MarkdownDetection.foldableHeadings`

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift:218-258`
- Modify: `Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift` (add tests)

- [ ] **Step 1: Write the failing test for ordinal disambiguation**

Append to `FoldableHeadingsTests.swift` before the closing `}`:
```swift
    // MARK: - Ordinal disambiguation (Decision 1)

    @Test("Duplicate H2 headings — second occurrence keyed with [2] suffix")
    func duplicateHeadingsOrdinalDisambiguation() {
        let text = "## Notes\nfirst\n## Notes\nsecond\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 2)
        #expect(headings[0].key == "## Notes")
        #expect(headings[1].key == "## Notes [2]")
    }

    @Test("Three duplicates produce [2] and [3] suffixes")
    func threeDuplicates() {
        let text = "## A\n1\n## A\n2\n## A\n3\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 3)
        #expect(headings.map { $0.key } == ["## A", "## A [2]", "## A [3]"])
    }

    @Test("Non-adjacent duplicates still get ordinals")
    func nonAdjacentDuplicates() {
        let text = "## A\n1\n## B\n2\n## A\n3\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 3)
        #expect(headings.map { $0.key } == ["## A", "## B", "## A [2]"])
    }

    @Test("Different-level same-text headings get separate ordinal counters")
    func differentLevelsSameText() {
        // `## A` and `### A` are not duplicates of each other; their level
        // prefixes differ, so each gets its own ordinal sequence.
        let text = "## A\n1\n### A\n2\n## A\n3\n### A\n4\n"
        let headings = MarkdownDetection.foldableHeadings(in: text)
        #expect(headings.count == 4)
        #expect(headings.map { $0.key } == ["## A", "### A", "## A [2]", "### A [2]"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Delegate to builder subagent: `xcodebuild -scheme Pommora test -destination 'platform=macOS' -only-testing:PommoraTests/FoldableHeadingsTests`
Expected: 13 prior tests pass, 4 new tests fail (keys are bare `"## Notes"` for both duplicates instead of `"## Notes"` + `"## Notes [2]"`).

- [ ] **Step 3: Implement ordinal disambiguation**

In `MarkdownDetection.swift`, replace the key-computation block inside `foldableHeadings(in:nsText:lineIndex:)` (around lines 235-256):

```swift
        // Pair each heading with its content range via the level-stack rule.
        // Track occurrence counts per (level, bareKey) so duplicates get an
        // ordinal `[N]` suffix starting at [2] (Decision 1, Plan §Locked
        // decisions). The first occurrence keeps the bare key; subsequent
        // occurrences with identical (level, bareKey) get `[2]`, `[3]`, etc.
        var result: [FoldedHeading] = []
        result.reserveCapacity(raws.count)
        var occurrenceCounts: [String: Int] = [:]
        for (i, raw) in raws.enumerated() {
            let headingLine = nsText.lineRange(
                for: NSRange(location: raw.astRange.location, length: 0)
            )
            let contentStart = headingLine.location + headingLine.length

            var contentEnd = nsText.length
            for j in (i + 1)..<raws.count where raws[j].level <= raw.level {
                contentEnd = raws[j].astRange.location
                break
            }

            let bareKey = nsText.substring(with: headingLine)
                .trimmingCharacters(in: .newlines)
            // Track duplicates per exact bareKey (which already encodes level
            // via the `#` prefix). First occurrence: bareKey. Subsequent:
            // bareKey + " [N]".
            let count = (occurrenceCounts[bareKey] ?? 0) + 1
            occurrenceCounts[bareKey] = count
            let key = count == 1 ? bareKey : "\(bareKey) [\(count)]"

            let contentRange = NSRange(
                location: contentStart,
                length: max(0, contentEnd - contentStart)
            )
            result.append(
                FoldedHeading(
                    key: key,
                    level: raw.level,
                    headingRange: headingLine,
                    contentRange: contentRange
                ))
        }
        return result
```

- [ ] **Step 4: Run tests to verify they pass**

Delegate to builder subagent: `xcodebuild -scheme Pommora test -destination 'platform=macOS' -only-testing:PommoraTests/FoldableHeadingsTests`
Expected: 17 tests passed (13 prior + 4 new).

- [ ] **Step 5: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift \
        Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift
git commit -m "feat(editor): ordinal disambiguation for duplicate heading keys (Decision 1)"
```

---

##### Task 4.2: Mirror ordinal logic in renderer's `headingKey` computation

The renderer needs the SAME key the detection produces so its hover/fold lookups against `coordinator.foldedHeadings` and `coordinator.hoveredHeadingKey` resolve correctly.

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift:154-164`

- [ ] **Step 1: Replace `headingKey` to walk preceding fragments and compute ordinal**

```swift
    /// Key for this heading fragment — exact source line stripped of any
    /// trailing newline, plus `[N]` ordinal suffix when this is the Nth
    /// occurrence of an identical source line in the document (Decision 1).
    /// Matches `FoldedHeading.key` shape produced by
    /// `MarkdownDetection.foldableHeadings(...)` so the renderer's hover /
    /// fold lookups against `coordinator.foldedHeadings` resolve correctly.
    @MainActor
    private var headingKey: String? {
        guard hasHeadingMarker,
            let myString = headingFragmentString,
            let myRange = nsRange,
            let ts = textStorage
        else { return nil }
        let bareKey = myString.trimmingCharacters(in: .newlines)

        // Count prior occurrences of this exact source line by walking
        // textStorage line-by-line from doc start to myRange.location.
        // O(N) per draw; cheap relative to TextKit 2's per-fragment work.
        let nsText = ts.string as NSString
        var count = 1
        var location = 0
        while location < myRange.location {
            let line = nsText.lineRange(for: NSRange(location: location, length: 0))
            let lineText = nsText.substring(with: line).trimmingCharacters(in: .newlines)
            if lineText == bareKey { count += 1 }
            let next = line.location + line.length
            if next <= location { break }
            location = next
        }
        return count == 1 ? bareKey : "\(bareKey) [\(count)]"
    }
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual duplicate-headings test**

Run the app. Create a page with two `## Notes` sections. Hover the first `## Notes`; click chevron — first section collapses, second stays visible. Hover the second `## Notes`; click chevron — second section collapses; first stays in whatever state it was. Confirm `folded_headings: ["## Notes [2]"]` (or similar) appears in the file's frontmatter after save.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift
git commit -m "feat(editor): mirror ordinal disambiguation in renderer headingKey"
```

---

##### Task 4.3: Mirror ordinal logic in hover handler's key computation

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift:66-100, 224-249`

The hover handler computes `key` at two sites:
- `updateHeadingFoldHover(at:)` line 98: `let key = fragmentString.trimmingCharacters(in: .newlines)`
- `handleHeadingChevronClick(at:)` line 249: `let key = fragmentString.trimmingCharacters(in: .newlines)`

Both need the ordinal disambiguation.

- [ ] **Step 1: Add a shared helper on the coordinator**

In `+HeadingFolding.swift`, add near the other static helpers:
```swift
    /// Compute the ordinal-disambiguated key for a heading line at
    /// `lineRange` in `nsText`. Mirrors `MarkdownDetection.foldableHeadings`'
    /// key-computation rule (Decision 1). O(N) document walk; called from
    /// hover/click hot paths but only when the cursor crosses a heading row.
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
```

- [ ] **Step 2: Replace both call sites in `NativeTextView+HeadingFoldHover.swift`**

At line 98:
```swift
let key = fragmentString.trimmingCharacters(in: .newlines)
```
becomes:
```swift
let key = NativeTextViewCoordinator.disambiguatedHeadingKey(
    forLineRange: nsRange, in: nsText
)
```

At line 249:
```swift
let key = fragmentString.trimmingCharacters(in: .newlines)
```
becomes:
```swift
let key = NativeTextViewCoordinator.disambiguatedHeadingKey(
    forLineRange: nsRange, in: textStorage.string as NSString
)
```

- [ ] **Step 3: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual hover test with duplicates**

Run the app with the duplicate-`## Notes` page from Task 4.2 still folded. Hover the first `## Notes` — chevron appears, pointing right (folded). Move to the second `## Notes` — chevron appears, pointing down (expanded). The hover state correctly distinguishes the two.

- [ ] **Step 5: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "feat(editor): hover handler uses disambiguated heading keys"
```

---

##### Task 4.4: Restore `unfocusCaretIfInsideFoldedRange` with cleaner conditional (Decision 2)

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift`

- [ ] **Step 1: Add the helper as a thin function**

Append at the end of the main extension block (before the delegate-conformance extension):
```swift
    /// Drop first-responder status when the current selection's leading edge
    /// would land inside any range in `foldedRanges` after the toggle. Used
    /// by the chevron click handler (Decision 2): preserve focus + caret
    /// position when safe; drop both only when the caret would otherwise
    /// vanish inside an elided range with no fragment to render it.
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
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift
git commit -m "feat(editor): conditional unfocus helper for chevron click (Decision 2)"
```

---

##### Task 4.5: Wire conditional unfocus into chevron click handler

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift` (the Phase-1 stand-in comment + unconditional `makeFirstResponder(nil)`)

- [ ] **Step 1: Replace the unconditional call with the conditional helper**

In `handleHeadingChevronClick(at:)`, find the Phase-1 stand-in block:
```swift
        // Phase-4 will replace this with conditional unfocus (Decision 2):
        // unconditional resignation here is a temporary stand-in so Phase 1
        // ships green. Final shape: only drop focus when the post-toggle
        // caret would otherwise land inside the freshly-folded range.
        window?.makeFirstResponder(nil)
```

Replace with:
```swift
        // Decision 2: drop first-responder only when the post-toggle caret
        // would otherwise land inside a freshly-folded range (no fragment
        // to render it). In every other case, the user's caret + selection
        // are preserved so chevron clicks don't interrupt active editing.
        coordinator.unfocusCaretIfInsideFoldedRange(self)
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual Decision-2 verification**

Run the app. Open a page with two sections.
- **Case A (preserve focus):** click into section 1's body; type a few characters; click chevron on section 2 (DIFFERENT section). Expected: section 2 collapses; caret stays in section 1; you can keep typing.
- **Case B (drop focus):** click into section 2's body; click chevron on section 2 (the SAME section the caret is in). Expected: section 2 collapses; caret disappears; you have to click somewhere to resume editing.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "feat(editor): wire conditional unfocus into chevron click (Decision 2)"
```

---

#### Phase 5: Orphan-key reconciliation on save

##### Task 5.1: Add `reconcileFoldedHeadings(in:)` helper

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift`

- [ ] **Step 1: Add the helper as a public static**

Append to the `MarkdownDetection` enum (inside the existing public enum block):
```swift
    /// Returns the subset of `foldedHeadings` whose keys still match an
    /// existing heading in `body`. Stale entries (keys whose corresponding
    /// heading was renamed or deleted) are dropped. Used by
    /// `PageEditorViewModel` before save to keep `folded_headings: [...]`
    /// from accumulating dead entries across rename cycles.
    public static func reconcileFoldedHeadings(
        _ foldedHeadings: Set<String>,
        in body: String
    ) -> Set<String> {
        guard !foldedHeadings.isEmpty else { return foldedHeadings }
        let currentKeys = Set(foldableHeadings(in: body).map { $0.key })
        return foldedHeadings.intersection(currentKeys)
    }
```

- [ ] **Step 2: Add tests for reconciliation**

Append to `FoldableHeadingsTests.swift`:
```swift
    // MARK: - Orphan-key reconciliation

    @Test("Reconciliation drops keys whose heading was renamed")
    func reconcileDropsRenamedHeading() {
        let body = "## Bar\nbody\n"  // user renamed "## Foo" -> "## Bar"
        let folded: Set<String> = ["## Foo"]
        let reconciled = MarkdownDetection.reconcileFoldedHeadings(folded, in: body)
        #expect(reconciled.isEmpty)
    }

    @Test("Reconciliation preserves keys that still match")
    func reconcilePreservesExistingHeading() {
        let body = "## Foo\nbody\n## Bar\nmore\n"
        let folded: Set<String> = ["## Foo", "## Stale"]
        let reconciled = MarkdownDetection.reconcileFoldedHeadings(folded, in: body)
        #expect(reconciled == ["## Foo"])
    }

    @Test("Reconciliation respects ordinal disambiguation")
    func reconcileWithOrdinals() {
        let body = "## A\n1\n## A\n2\n"
        // User had three duplicates folded; document now has only two.
        let folded: Set<String> = ["## A", "## A [2]", "## A [3]"]
        let reconciled = MarkdownDetection.reconcileFoldedHeadings(folded, in: body)
        #expect(reconciled == ["## A", "## A [2]"])
    }
```

- [ ] **Step 3: Run tests to verify they pass**

Delegate to builder subagent: `xcodebuild -scheme Pommora test -destination 'platform=macOS' -only-testing:PommoraTests/FoldableHeadingsTests`
Expected: 20 tests passed (17 prior + 3 new).

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift \
        Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift
git commit -m "feat(editor): add reconcileFoldedHeadings helper + tests"
```

---

##### Task 5.2: Wire reconciliation into `PageEditorViewModel.flushNow`

**Files:**
- Modify: `Pommora/Pommora/Pages/PageEditorViewModel.swift`

- [ ] **Step 1: Read the slice of `flushNow` to find the save-call site**

Read `PageEditorViewModel.swift` lines 74-130 (just past `flushNow`'s opening).

- [ ] **Step 2: Insert reconciliation before the save call**

At the start of `flushNow()`'s body, before any save operation, insert:
```swift
        // Drop stale fold-state keys (heading text changed or deleted) so
        // `folded_headings:` doesn't accumulate dead entries across saves.
        // Mutating `foldedHeadings` here would re-fire scheduleSave and
        // recurse — write directly to the frontmatter instead.
        let reconciled = MarkdownDetection.reconcileFoldedHeadings(foldedHeadings, in: body)
        if reconciled != foldedHeadings {
            foldedHeadings = reconciled  // didSet mirrors to frontmatter
        }
```

The `didSet` on `foldedHeadings` already handles mirroring to `page.frontmatter.foldedHeadings`, so reassigning the Set is the correct path. The `scheduleSave()` it triggers is harmless during `flushNow` (the next debounce just no-ops if `body`/`foldedHeadings` are unchanged after this call returns).

- [ ] **Step 3: Add `import MarkdownEngine` if not already present**

Check the imports at the top of `PageEditorViewModel.swift`. If `MarkdownEngine` is not imported, add it.

- [ ] **Step 4: Build + test verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora test -destination 'platform=macOS' -only-testing:PommoraTests/PageEditorViewModelTests`
Expected: `** TEST SUCCEEDED **` with the existing PageEditorViewModel suite.

- [ ] **Step 5: Manual rename verification**

Run the app. Open a page with `## Foo` folded (`folded_headings: ["## Foo"]` in frontmatter). Rename the heading to `## Bar`. Wait 350ms (past the save debounce) — verify the file's frontmatter no longer contains `folded_headings:` (the key was dropped on reconciliation; the Set became empty; encoder skips nil-or-empty).

- [ ] **Step 6: Commit**

```bash
git add Pommora/Pommora/Pages/PageEditorViewModel.swift
git commit -m "feat(editor): reconcile fold-state on save to drop orphan keys"
```

---

#### Phase 6: Hot-path cleanup

##### Task 6.1: Convert tracking area to single-create on view setup

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift:28-42`

- [ ] **Step 1: Replace `updateTrackingAreas` body**

```swift
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Tracking area is created once on first call with `.inVisibleRect`
        // so it auto-tracks the visible rect across scroll / resize without
        // tear-down + recreate. Subsequent `updateTrackingAreas` calls are
        // no-ops because the area already exists.
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
```

- [ ] **Step 2: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual scroll-during-hover verification**

Run the app. Open a long page. Hover a heading near the top; chevron appears. Scroll down (with two-finger trackpad) while keeping cursor still — chevron updates correctly as the heading moves out of view. Scroll back up — hover state re-acquires on the same heading.

- [ ] **Step 4: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "perf(editor): single-create tracking area with .inVisibleRect"
```

---

##### Task 6.2: Unify the triple hit-test into a single helper

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift`

- [ ] **Step 1: Add a unified hit-test helper**

Add near the top of the file (after `updateTrackingAreas`):
```swift
    /// Single hit-test consumed by `updateHeadingFoldHover`,
    /// `updateHeadingChevronCursor`, and `handleHeadingChevronClick`.
    /// Returns the (fragment, nsRange, key, chevronRect) tuple OR nil when
    /// `viewPoint` doesn't land on a heading row. Replaces the prior
    /// three-times-per-mouseMoved redundant lookups.
    struct HeadingHitTest {
        let fragment: NSTextLayoutFragment
        let nsRange: NSRange
        let key: String
        let chevronRect: CGRect
    }

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
```

- [ ] **Step 2: Refactor `updateHeadingFoldHover` to use the helper**

Replace the function body (lines 66-100):
```swift
    private func updateHeadingFoldHover(at viewPoint: CGPoint) {
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return }
        guard let hit = headingHitTest(at: viewPoint) else {
            applyHoveredHeadingKey(nil, in: coordinator)
            return
        }
        applyHoveredHeadingKey(hit.key, in: coordinator)
    }
```

- [ ] **Step 3: Refactor `updateHeadingChevronCursor` + `isPointInsideHeadingChevronHitZone`**

Replace `isPointInsideHeadingChevronHitZone` (lines 312-327) and simplify the cursor handler:
```swift
    /// True when `viewPoint` lands inside a hovered heading's chevron
    /// hit-zone (6pt-inflated chevron rect).
    private func isPointInsideHeadingChevronHitZone(_ viewPoint: CGPoint) -> Bool {
        guard let hit = headingHitTest(at: viewPoint) else { return false }
        return hit.chevronRect.insetBy(dx: -6, dy: -6).contains(viewPoint)
    }
```

- [ ] **Step 4: Refactor `handleHeadingChevronClick(at:)` to use the helper**

Replace the click handler's hit-test prologue (lines 224-249):
```swift
    func handleHeadingChevronClick(at viewPoint: CGPoint) -> Bool {
        guard let coordinator = delegate as? NativeTextViewCoordinator,
            let textStorage = textStorage,
            let hit = headingHitTest(at: viewPoint)
        else { return false }
        // 6pt tolerance around the 12pt glyph — keeps the chevron clickable
        // without making the hit zone bleed into the heading text on the
        // right side or onto adjacent rows above/below.
        guard hit.chevronRect.insetBy(dx: -6, dy: -6).contains(viewPoint) else { return false }
        let key = hit.key
        let willBeFolded: Bool
        if coordinator.foldedHeadings.contains(key) {
            coordinator.foldedHeadings.remove(key)
            willBeFolded = false
        } else {
            coordinator.foldedHeadings.insert(key)
            willBeFolded = true
        }
        coordinator.applyFoldStateIfChanged(in: textStorage, textView: self)
        coordinator.startChevronAnimation(
            forHeadingKey: key, toFolded: willBeFolded, textView: self
        )
        // Decision 2: drop first-responder only when the post-toggle caret
        // would otherwise land inside a freshly-folded range. Otherwise
        // preserve focus so chevron clicks don't interrupt active editing.
        coordinator.unfocusCaretIfInsideFoldedRange(self)
        return true
    }
```

- [ ] **Step 5: Build + manual verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

Manual: hover, click, cursor swap all behave identically to pre-unification (visual + interaction unchanged).

- [ ] **Step 6: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift
git commit -m "perf(editor): unify chevron hit-test into single helper"
```

---

##### Task 6.3: Try `invalidateRenderingAttributes` for chevron animation redraws

**Files:**
- Modify: `External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift` (`nudgeHeading` / `chevronAnimationTick`)

This task is experimental — the engine team's prior note said `invalidateRenderingAttributes` didn't trigger redraw. Re-trying now that the restyle pipeline is lighter post-rebuild. If it works, drop `nudgeAttributes` entirely. If not, keep nudge with a clearer comment.

- [ ] **Step 1: Add a `kickRenderingAttributes(forHeadingKey:in:)` alternative path**

Add this function next to `nudgeHeading`:
```swift
    /// Experimental redraw trigger using TextKit 2's documented rendering-
    /// attribute invalidation API. Lighter than `nudgeHeading` (no edit
    /// cascade), but the prior engine investigation suggested it didn't
    /// trigger imperative `draw(at:in:)` re-runs. Re-evaluated post-content-
    /// elision rebuild because the restyle pipeline is now simpler — if
    /// this DOES trigger redraw reliably, `nudgeHeading` can be retired.
    func kickRenderingAttributes(forHeadingKey key: String, in textView: NSTextView) {
        guard let ts = textView.textStorage,
            let tlm = textView.textLayoutManager,
            let tcs = tlm.textContentManager as? NSTextContentStorage
        else { return }
        let nsText = ts.string as NSString
        guard let lineRange = Self.headingLineRange(forKey: key, in: nsText),
            let startLoc = tcs.location(tcs.documentRange.location, offsetBy: lineRange.location),
            let endLoc = tcs.location(tcs.documentRange.location, offsetBy: lineRange.location + lineRange.length),
            let textRange = NSTextRange(location: startLoc, end: endLoc)
        else { return }
        tlm.invalidateRenderingAttributes(for: textRange)
    }
```

- [ ] **Step 2: Swap `nudgeHeading` → `kickRenderingAttributes` in the chevron animation tick (TEST PATH)**

Don't permanently change `chevronAnimationTick` yet. First add a feature flag at the top of the coordinator extension:
```swift
    /// If true, chevron rotation animation uses `invalidateRenderingAttributes`
    /// instead of the heavier `nudgeAttributes` paragraphStyle write. Set to
    /// false to revert if rotation flickers or stalls.
    static let useRenderingAttributesForChevronRedraw = true
```

In `chevronAnimationTick(_:)`, replace both `nudgeAttributes` calls (the in-flight and completed loops) with:
```swift
                if Self.useRenderingAttributesForChevronRedraw {
                    // Lighter path — direct rendering-attr invalidation.
                    if let key = anim.key {  // need to thread key through ChevronAnimation
                        kickRenderingAttributes(forHeadingKey: key, in: textView)
                    }
                } else {
                    // Heavier fallback via paragraphStyle write + edit cascade.
                    nudgeAttributes(in: ts, range: range)
                }
```

Note: this requires adding `let key: String` to `ChevronAnimation` struct so the tick has access to the key (currently it only has `headingRange: NSRange?`).

Update `ChevronAnimation` struct in `NativeTextViewCoordinator.swift` lines 113-119:
```swift
    struct ChevronAnimation: Sendable {
        let key: String  // NEW: needed for kickRenderingAttributes lookup
        let startAngle: CGFloat
        let targetAngle: CGFloat
        let startTime: TimeInterval
        let duration: TimeInterval
        let headingRange: NSRange?
    }
```

Update `startChevronAnimation` constructor to include `key:`.

- [ ] **Step 3: Build verification**

Delegate to builder subagent: `xcodebuild -scheme Pommora -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual animation verification**

Run the app. Click a chevron. Expected: chevron rotates smoothly over ~200ms between right (0°) and down (π/2). If rotation stutters, freezes, or doesn't redraw at all, set `useRenderingAttributesForChevronRedraw = false` in the file and re-build — falls back to `nudgeAttributes`.

If the lighter path works reliably, plan to remove `nudgeHeading` + `nudgeAttributes` + the feature flag in a follow-up patch. If not, keep both paths and document the tradeoff in §9.11.

- [ ] **Step 5: Commit**

```bash
git add External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift \
        External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift
git commit -m "perf(editor): try invalidateRenderingAttributes for chevron rotation redraws"
```

---

#### Phase 7: Documentation + NOTICE updates

##### Task 7.1: Rewrite `Markdown.md §9.11` for the shipped architecture

**Files:**
- Modify: `.claude/Guidelines/Markdown.md` lines 447-494 (Studio)
- Mirror: `/Users/nathantaichman/The Nexus/Pages/Pommora/Guidelines/Markdown.md` (same section)

- [ ] **Step 1: Replace the WIP banner + the "Current state of the collapse layer" sub-section**

The current WIP banner + sub-section was added during pre-rebuild documentation. Replace them with a shipped-status banner:

```markdown
##### 9.11 Foldable headings — content-manager elision (v0.2.x)

**Status:** ✅ SHIPPED. Hover a heading line → chevron appears in left gutter; click toggles a true zero-height collapse of the content under that heading (down to the next equal-or-higher heading or document end). Chevron rotates 0 → π/2 over 200ms ease-in-out between right (folded) and down (expanded). Per-Page state persists via `folded_headings: [String]` in YAML frontmatter; renaming a heading drops its entry; orphan keys reconciled on save. Duplicate-text headings disambiguated via `[N]` ordinal suffix. Caret + selection preserved on chevron click unless the caret would otherwise vanish inside the freshly-folded range (conditional unfocus).
```

Then delete the "Current state of the collapse layer (the open problem)" subsection (about 8 lines starting `###### Current state...`).

- [ ] **Step 2: Rewrite the renderer-row of the architecture table**

The current table's renderer row says "Overrides `layoutFragmentFrame` to report `height = 0`..." — that's the abandoned approach. Replace with:

```markdown
| **Renderer** | Reads `coordinator.foldedRanges` only for the chevron-rotation animation (the elided content has no fragments at all). Draws the chevron via SF Symbol `chevron.right` rotated by `coordinator.currentChevronAngle(...)` in `draw(at:in:)` when this fragment is the hovered heading. | [`Renderer/MarkdownTextLayoutFragment.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) |
```

Add a new row above the table for the content-storage delegate:
```markdown
| **Content elision** | `NativeTextViewCoordinator` conforms to `NSTextContentStorageDelegate`; `textContentStorage(_:textParagraphWith:)` returns an empty `NSTextParagraph` for source ranges intersecting `foldedRanges`. The layout manager sees no content for those ranges — zero fragments, zero layout space, unreachable to selection/find/spell-check. | [`+HeadingFolding.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift) |
```

- [ ] **Step 3: Replace the "Why a true zero-height collapse" subsection**

The current subsection (around lines 469-471) describes the abandoned `layoutFragmentFrame` approach. Replace with:

```markdown
###### Why content-manager elision, not a layout-level hide

Hiding fragments at the layout layer (via `layoutFragmentFrame` override OR via attribute-write fold-hide) was tried in two rounds and failed both times. Root cause: `NSTextViewportLayoutController` is aggressive about re-flowing downstream fragments when fragments GROW but lazy when they SHRINK. Combined with stored-property caching on `layoutFragmentFrame` and CoreText line-height floors that don't truly produce zero-height fragments, neither layout-level approach delivers true collapse. The canonical TextKit 2 primitive — `NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)` returning an empty `NSTextParagraph` — elides the content from the layout model entirely. Zero fragments → zero height naturally → no patches needed for caret-skip, selection-collapse, or post-toggle restyle.
```

- [ ] **Step 4: Drop the `isSyncingHeadingFolds` lie**

Around line 488, the section "Reentry guards in this construct" mentions `isSyncingHeadingFolds`. That flag never existed. Delete that bullet entry; keep the other two (`isPushingCaretOutOfFold` — also delete, since Phase 1 stripped it; `isProgrammaticEdit` — keep, note "not used here"). The reentry-guards subsection becomes:

```markdown
###### Reentry guards in this construct

- `isProgrammaticEdit` — not used here; the service doesn't write to `textStorage` at all (no attribute writes; content elision happens via delegate vending).
- Implicit guard: `applyFoldStateIfChanged` early-returns when `foldedHeadings == lastSyncedFoldedHeadings`, which protects against re-entry from SwiftUI's binding-driven `updateNSView` cascade.
```

- [ ] **Step 5: Mirror the same edits to Nexus**

Apply the same four edits to `/Users/nathantaichman/The Nexus/Pages/Pommora/Guidelines/Markdown.md` §9.11.

- [ ] **Step 6: Diff verification**

```bash
diff "/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/Guidelines/Markdown.md" \
     "/Users/nathantaichman/The Nexus/Pages/Pommora/Guidelines/Markdown.md"
```
Expected: empty output (mirrors identical).

- [ ] **Step 7: Commit**

```bash
git add .claude/Guidelines/Markdown.md
git commit -m "docs(editor): rewrite §9.11 for shipped content-elision architecture"
```

---

##### Task 7.2: Promote `PageEditor.md` + `Pages.md` from WIP to SHIPPED

**Files:**
- Modify: `.claude/Features/PageEditor.md:141`
- Modify: `.claude/Features/Pages.md:33`
- Mirror both to Nexus.

- [ ] **Step 1: PageEditor.md:141 — promote**

Replace:
```markdown
- **Foldable headings — WIP (not shipped).** ...
```
with:
```markdown
- **Foldable headings — SHIPPED.** Hover any heading line → chevron appears in the left gutter; click toggles a true zero-height collapse of the section under that heading (down to the next equal-or-higher heading, or document end). Chevron rotates over 200ms ease-in-out between right (folded ▶) and down (expanded ▼). Caret + selection preserved unless the caret would otherwise land inside the freshly-folded range (conditional unfocus). Per-Page fold state persists via the frontmatter key `folded_headings: ["## Foo", ...]`; renaming a heading drops its entry (orphan reconciliation on save). Duplicate-text headings get `[N]` ordinal suffixes for independent fold targeting. Architecture: content-manager elision via `NSTextContentStorageDelegate` — documented in `// Guidelines//Markdown.md` §9.11.
```

- [ ] **Step 2: Pages.md:33 — promote**

Replace:
```markdown
- Paragraphs, **headings** (H1–H5 in v0's type scale; no H6 token). **Foldable headings — WIP (not shipped).** ...
```
with:
```markdown
- Paragraphs, **headings** (H1–H5 in v0's type scale; no H6 token). **Headings are foldable by default** — hover any heading line to reveal a chevron in the left gutter; click it to collapse the section below that heading (down to the next equal-or-higher heading, or document end) to zero height. Fold state persists per-Page in frontmatter as `folded_headings: ["## Foo", ...]` (exact heading source line keys; renaming a heading drops its entry; orphan keys reconciled on save). Duplicate-text headings disambiguated via `[N]` ordinal suffix. The Markdown body itself is untouched — external tools see standard headings with no fold notion. Implementation spec → [[PageEditor]]; architecture rationale → `// Guidelines//Markdown.md` §9.11.
```

- [ ] **Step 3: Mirror both to Nexus**

Apply the same edits to:
- `/Users/nathantaichman/The Nexus/Pages/Pommora/Features/PageEditor.md`
- `/Users/nathantaichman/The Nexus/Pages/Pommora/Features/Pages.md`

- [ ] **Step 4: Diff verification**

```bash
diff "/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/Features/PageEditor.md" \
     "/Users/nathantaichman/The Nexus/Pages/Pommora/Features/PageEditor.md"
diff "/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/Features/Pages.md" \
     "/Users/nathantaichman/The Nexus/Pages/Pommora/Features/Pages.md"
```
Both expected: empty output.

- [ ] **Step 5: Commit**

```bash
git add .claude/Features/PageEditor.md .claude/Features/Pages.md
git commit -m "docs(editor): promote foldable-headings status from WIP to shipped"
```

---

##### Task 7.3: Rewrite `NOTICE.md` foldable-headings entries

**Files:**
- Modify: `External/MarkdownEngine/NOTICE.md:31-40`

The 10 v0.2.x foldable-headings entries currently describe the abandoned layoutFragmentFrame + attribute-write approach. Rewrite them to reflect content-manager elision.

- [ ] **Step 1: Replace the 10 entries**

Replace lines 31-40 with:

```markdown
| v0.2.x (foldable headings) | EXTEND | `Parser/MarkdownDetection.swift` | Adds top-level `public struct FoldedHeading` (key + level + headingRange + contentRange); promotes `enum MarkdownDetection` to `public`; adds `isHeadingLine(_:isInsideCodeBlock:)` Stage 0/1/2 helper; adds `public static func foldableHeadings(in:)` overloads with ordinal `[N]` disambiguation for duplicate-text headings; adds `public static func reconcileFoldedHeadings(_:in:)` for orphan-key cleanup on save |
| v0.2.x (foldable headings) | EXTEND | `Renderer/MarkdownTextLayoutFragment.swift` | Adds heading-fragment helpers (`headingFragmentString`, `hasHeadingMarker`, `headingKey` with ordinal disambiguation, `isHoveredHeading`, `isHeadingFolded`, `chevronRect(at:)` via shared `HeadingChevronGeometry`); adds `drawHeadingChevron(at:in:)` (rotated SF Symbol `chevron.right` per coordinator's animated angle); extends `renderingSurfaceBounds` to union with chevron rect when `hasHeadingMarker`; wires call as the 8th step in `draw(at:in:)` |
| v0.2.x (foldable headings) | EXTEND | `TextView/Coordinator/NativeTextViewCoordinator.swift` | Adds `@Binding var foldedHeadings: Set<String>` (defaulted to `.constant([])`); state fields `foldedRanges`, `hoveredHeadingKey`, `lastSyncedFoldedHeadings`, `chevronAnimations` + `chevronAnimationTimer`; nested `struct ChevronAnimation`; extends init with `foldedHeadings:` parameter |
| v0.2.x (foldable headings) | NEW | `TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift` | Service file with two responsibilities: (1) `NSTextContentStorageDelegate` conformance + `textContentStorage(_:textParagraphWith:)` returning empty `NSTextParagraph` for source ranges intersecting `foldedRanges` — the elision primitive; (2) `syncHeadingFolding(in:textView:)` walks AST and rebuilds `foldedRanges`, `applyFoldStateIfChanged(in:textView:)` is the fold-toggle path that diffs against `lastSyncedFoldedHeadings` and calls `invalidateLayout(for:)` on the affected range, `unfocusCaretIfInsideFoldedRange(_:)` is the conditional-unfocus path called from chevron click (Decision 2). Also hosts the chevron rotation animation (`currentChevronAngle`, `startChevronAnimation`, `chevronAnimationTick`, `kickRenderingAttributes`) |
| v0.2.x (foldable headings) | EXTEND | `TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift` | Wires `syncHeadingFolding(in:textView:)` after `syncHRVisibility` in both `rebuildTextStorageAndStyle` (initial load) and `restyleTextView` (per-edit hot path) so heading edits propagate to fold ranges immediately |
| v0.2.x (foldable headings) | EXTEND | `TextView/NativeTextView/NativeTextView.swift` | Adds `var headingFoldHoverTrackingArea: NSTrackingArea?` stored property |
| v0.2.x (foldable headings) | NEW | `TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift` | Hover detection: single-create NSTrackingArea (`.inVisibleRect`, no per-scroll rebuild); unified `headingHitTest(at:)` consumed by `mouseMoved`, cursor swap, and click handler; `handleHeadingChevronClick(at:)` mutates `coordinator.foldedHeadings`, calls `applyFoldStateIfChanged` synchronously, starts chevron rotation animation, and calls `unfocusCaretIfInsideFoldedRange` (Decision 2) |
| v0.2.x (foldable headings) | EXTEND | `TextView/NativeTextView/NativeTextView+DragSelectBoost.swift` | Adds `handleHeadingChevronClick(at:)` hit-test into existing `mouseDown(with:)` before the autoscroll-boost timer arms |
| v0.2.x (foldable headings) | EXTEND | `TextView/NativeTextViewWrapper.swift` | Adds `@Binding public var foldedHeadings: Set<String>` parameter (defaulted to `.constant([])`); passes through `makeCoordinator`; wires `textContentStorage.delegate = coordinator` in `makeNSView` before first layout pass (so initial-load folds apply before any visible render); adds `coordinator.applyFoldStateIfChanged(in:textView:)` in the text-unchanged early-return branch so fold-only updates propagate |
| v0.2.x (foldable headings) | NEW | `Util/HeadingChevronGeometry.swift` | Shared chevron-rect computation consumed by renderer and hover handler (L2) |
| v0.2.x (foldable headings) | NEW | `Util/NSTextLayoutFragment+NSRange.swift` | Shared `var nsRange: NSRange?` extension consumed by renderer and hover handler (L2) |
```

- [ ] **Step 2: Commit**

```bash
git add External/MarkdownEngine/NOTICE.md
git commit -m "docs(editor): update NOTICE.md ledger for foldable-headings v0.2.x shipped state"
```

---

#### Phase 8: Manual UX verification (no commit — pre-merge sanity)

Run the app via `xcodebuild -scheme Pommora -destination 'platform=macOS' build` and launch the built binary. Confirm each item below before declaring the feature shipped.

- [ ] **8.1 Cold-open with pre-folded page** — open a `.md` file whose frontmatter has `folded_headings: ["## Some Section"]`. The section opens already collapsed — no flash of expanded content.
- [ ] **8.2 Click chevron — collapse** — click an expanded heading's chevron. Content under it disappears instantly (zero height). Subsequent headings move up to fill the space.
- [ ] **8.3 Click chevron — expand** — click a folded heading's chevron. Content reappears at its original height. Subsequent headings shift back down.
- [ ] **8.4 Chevron rotation** — chevron animates over ~200ms between right (folded) and down (expanded). No stutter, no flicker.
- [ ] **8.5 Hover transitions** — moving the cursor across multiple headings cleanly shows/hides chevrons row by row. No ghost chevrons stuck on screen.
- [ ] **8.6 Conditional unfocus (Decision 2 — preserve)** — caret inside section A; click chevron on section B (different section). Section B collapses; caret stays in A; typing continues.
- [ ] **8.7 Conditional unfocus (Decision 2 — drop)** — caret inside section A; click chevron on section A (same section). Section A collapses; caret disappears; clicking elsewhere restores caret.
- [ ] **8.8 Duplicate heading independence (Decision 1)** — page with two `## Notes` sections. Folding the first does not fold the second. Saving the file shows `folded_headings: ["## Notes"]`; folding the second shows `folded_headings: ["## Notes [2]"]`.
- [ ] **8.9 Orphan reconciliation** — page with `## Foo` folded. Rename to `## Bar`. Save (wait 350ms past debounce). Reopen file — verify `folded_headings:` is absent from frontmatter (key was dropped).
- [ ] **8.10 Persistence round-trip** — fold several headings. Quit Pommora. Reopen. Same sections come back folded.
- [ ] **8.11 Selection across fold** — cursor above a folded section; Shift+Down repeatedly. Selection extends past the fold to the next visible content. No invisible characters captured.
- [ ] **8.12 Find-in-document inside fold** — Cmd+F a string that exists only inside a folded section. Note current behavior (highlights may or may not appear depending on TextKit's find implementation). If find skips folded content, that's correct content-elision behavior. If it highlights inside, document as a known limitation.
- [ ] **8.13 Scroll past fold** — fold a long section; scroll. Scroll position respects the new (smaller) content height. No phantom whitespace where the folded content used to be.
- [ ] **8.14 Large-doc mouseMoved perf** — open a long doc (>500 lines, 50+ headings). Move the cursor across multiple headings. No visible lag in chevron appear/disappear.
- [ ] **8.15 Restyle does not unfold** — fold a section. Edit text inside a different section. The folded section stays folded.

If any item fails, file as a follow-up; do not block ship unless 8.1-8.4 or 8.6-8.10 fail (the locked-decision items).

---

#### Self-review checklist

- [ ] **Spec coverage** — every locked decision and every audit finding has a task that implements it: Decision 1 (Task 4.1, 4.2, 4.3, tests in 4.1 + 5.1), Decision 2 (Task 4.4, 4.5), content elision (Task 3.1, 3.2, 3.3, 3.4), orphan reconciliation (Task 5.1, 5.2), all four L2 deduplications (Task 2.1-2.5), all six STRIP items (Task 1.1-1.6), tracking-area cleanup (Task 6.1), unified hit-test (Task 6.2), rendering-attributes experiment (Task 6.3), all four doc updates (Task 7.1-7.3). ✅
- [ ] **Placeholder scan** — every step contains exact code, exact paths, exact commands. No "TBD", "implement later", "add appropriate error handling." ✅
- [ ] **Type consistency** — `foldedHeadings` (Set<String>), `foldedRanges` ([NSRange]), `hoveredHeadingKey` (String?), `lastSyncedFoldedHeadings` (Set<String>), `ChevronAnimation` (struct), `HeadingHitTest` (nested struct), `HeadingChevronGeometry` (enum), `FoldedHeading` (public struct), `disambiguatedHeadingKey(forLineRange:in:)` (static), `reconcileFoldedHeadings(_:in:)` (public static), `unfocusCaretIfInsideFoldedRange(_:)` (instance), `kickRenderingAttributes(forHeadingKey:in:)` (instance). All names consistent across tasks. ✅
- [ ] **Studio rules** — no h1 or h2 headings (h3 max); no timelines anywhere in the plan; phases not dates; planning lives in `.claude/Planning/`. ✅
- [ ] **Quirks honored** — quirk #1 (filename-form test filters), quirk #2 (PBXFileSystemSynchronizedRootGroup auto-includes), quirk #3 (trust xcodebuild not SourceKit), quirk #8 (each phase ships green standalone), quirk #11 (don't bundle unattributed working-tree changes), quirk #12 (`swift format format --in-place`). Referenced where relevant. ✅

---

#### Execution handoff

Plan complete and saved. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Best for a rebuild this large because each task's context is small and reviewable in isolation.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints. Better if you want to watch each step land in real time.

Which approach?
