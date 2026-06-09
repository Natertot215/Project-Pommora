## Item Window UIX Sweep — Implementation Plan

> **For agentic workers:** execute via `superpowers:subagent-driven-development`. Steps use `- [ ]` checkboxes. Spec/“what+why” lives in `06-08-ItemWindow-UIX-Sweep.md`; this is the “how”, task-by-task. Branch: `itemsv2-interactive-window` (HEAD `91e53b3`).

**Goal:** Transform the committed non-activating `NSPanel` Item Window into the locked Figma design (fixed-size panel, v1 ✕ chrome, body-fills, unified hairline inspector, zero dimming) and fix the select/status apply-on-click bug.

**Architecture:** AppKit `NSPanel` (`FloatingItemPanel`) hosts SwiftUI via `NSHostingController`; content is `ItemWindowHost → ItemWindowRenderer` (main column + native `.inspector { ItemInspector }`). Per-Nexus managers injected via `.injectNexusEnvironment`. All edits route through `ItemWindowViewModel` seams.

**Tech stack:** Swift 6 (strict concurrency + ExistentialAny), SwiftUI + AppKit, macOS 26.4 target, Swift Testing. Build/verify via background `builder` agent (quirk #13), test filter `-only-testing:PommoraTests/ItemWindowViewModelTests` (verified suite name, quirk #1).

### Execution model (the per-task loop)

Each task: implementer subagent authors → background `builder` verifies (compiles green + non-zero `ItemWindowViewModelTests`) → I read the diff → green-commit. **Most of this sweep is SwiftUI layout/AppKit behavior that is NOT unit-testable** (confirmed: `ItemWindowViewModelTests` covers pure VM logic only). So the gates are: (1) compiler green, (2) existing tests still pass non-zero, (3) **Nathan’s real-build review at T7** for every visual + the focus/dimming behavior. Where a pure-logic seam exists (T4 placeholder predicate), add a unit test.

### File map

| File | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|---|
| `ItemWindow/FloatingItemPanel.swift` | ✎ fixed size, hide buttons | ✎ active-appearance | | | | |
| `ItemWindow/ItemWindowRenderer.swift` | ✎ header (✕/title), main flexes | | ✎ body fills | ✎ un-gate bar | | |
| `ItemWindow/PropertyFieldBar.swift` | | | | ✎ placeholder mode | | |
| `ItemWindow/ItemInspector.swift` | | | | | ✎ full rewrite | |
| `ItemWindow/PropertyEditorRow.swift` | | | | | (icon in row) | ✎ status trigger+popover |
| `DesignSystem/PUI.swift` | ✎ ItemWindow dims | | | | | |

Reference-only (do NOT edit): `Window/PreviewWindow.swift` (✕ source), `Properties/PropertyPanel.swift` (hairline pattern), `Properties/ContextValueEditor.swift` (tier editor + Add), `Detail/Columns/PropertyCellEditor.swift` (correct status pattern), `ContentView.swift` (Pages `.inspector` reference).

### Design decisions this plan BAKES IN — confirm before/at execution

These are judgment calls the plan makes that Nathan has not explicitly ratified. Flagged per his instruction. Defaults chosen are noted; correcting any is cheap now, expensive later.

1. **Exact size = 800×560**, and `PUI.ItemWindow` constants get rewritten (today’s `totalWidth 760 / mainWidth 480 / inspectorWidth 260 / height 480` become a fixed `width 800 / height 560`; `mainWidth` is deleted since the main column now flexes). → confirm 800×560 + the constant cleanup.
2. **Inspector width** within the fixed 800: default `min 240 / ideal 300 / max 420` (the frame shows it ≈¼, so ideal ≈260–300). The split divider stays user-draggable. → confirm ideal width + draggable-split OK.
3. **Title font** = `.headline`-weight system title (true “standard window title”, ~13–15pt). The Figma frame’s title reads a touch larger; if you want the frame’s size, it’s `.title3`. Default: `.headline`. → confirm which.
4. **Group separator** between contexts and properties (no text headers): default = the same hairline `Divider` as between rows, plus a small extra top gap on the first property row so the two groups read as distinct. → confirm (vs a heavier full-width rule).
5. **Property-bar placeholder**: default = 3 plain “Label” cells + 3 grey pill “Label” cells (matching the frame), non-interactive. Grey pill = inline `Capsule().fill(Color(.systemFill))` (NOT a new `PropertyChipColor` case, to avoid polluting the schema enum). → confirm count/mix + the no-new-enum-case choice.
6. **Empty-tier affordance** = reuse `ContextValueEditor`’s existing “⊕ Add” trigger (the current build’s look). → confirm (vs a custom empty treatment).
7. **Unified row builder** = a layout-shell `inspectorRow(icon:label:) { editor }` that wraps BOTH tier rows (editor = `ContextValueEditor`) and property rows (editor = `PropertyEditorRow`). It unifies geometry, not data types. → confirm the DRY-shell approach.
8. **Property rows gain a leading icon** (`def.displayIcon`) to match the contexts’ `[icon][label]` shape — current property rows have no icon. → confirm adding the icon.
9. **Title stays inline-editable** (rename on commit, as today). → confirm (vs display-only).
10. **T2 dimming = a SPIKE, not a known fix.** Mechanism is unverifiable from the SDK. Plan: try `.environment(\.controlActiveState, .active)`; if it doesn’t compile or has no effect, fall back to an AppKit `FloatingItemPanel` override forcing active appearance; if neither lands cleanly, ship T1’s hidden-traffic-lights + custom ✕ (which already removes the loudest cue) and report the residual honestly. → confirm you accept a spike here, verified in your build.

### Tasks

#### T1 — Fixed size + header chrome

**Files:** `FloatingItemPanel.swift`, `ItemWindowRenderer.swift`, `PUI.swift`.

- [ ] **PUI:** rewrite `enum ItemWindow` to a fixed `width: CGFloat = 800`, `height: CGFloat = 560`; delete `mainWidth`, `totalWidth`, `inspectorWidth` (or repurpose only what’s referenced — grep first).
- [ ] **FloatingItemPanel:** drop `hosting.sizingOptions = .preferredContentSize` (line 22); set `contentRect` to `NSRect(x:0,y:0,width:800,height:560)`. After all config in `init`, hide all three native buttons:
  ```swift
  standardWindowButton(.closeButton)?.isHidden = true
  standardWindowButton(.miniaturizeButton)?.isHidden = true
  standardWindowButton(.zoomButton)?.isHidden = true
  ```
  Keep `.closable` in the styleMask (preserves ⌘W). Pin the hosted content to the fixed size (`.frame(width: 800, height: 560)` on the root, since `.preferredContentSize` no longer drives it — verify the panel doesn’t resize).
- [ ] **Renderer body:** change `mainColumn.frame(width: PUI.ItemWindow.mainWidth)` → `.frame(maxWidth: .infinity)` so the main column flexes and the `.inspector` takes width from it within the fixed 800.
- [ ] **Renderer header:** prepend the v1 ✕ (mirror `PreviewWindow.swift:51-62`: `Image(systemName:"xmark")`, `.system(size:11,weight:.semibold)`, `.secondary`, 22×22, `.buttonStyle(.plain)`) wired to `AppGlobals.current?.itemWindowPanelManager.close(ref)`. Icon button stays second (flush after ✕). Title `TextField`: add `.lineLimit(1)`, `.truncationMode(.tail)`, `.frame(maxWidth:.infinity, alignment:.leading)`, font → window-title style (decision #3). Remove `.padding(.leading, 56)` (the native-button clearance) → symmetric `PUI.Spacing.md`.
- [ ] **Verify:** background builder, compile green + non-zero tests. Diff review. **Runtime (Nathan, T7):** fixed size both inspector states; ✕ closes; no native buttons; long title truncates without pushing the toggle.
- [ ] **Commit:** `feat(item-window): fixed-size panel + v1 ✕ chrome; main column flexes`

#### T2 — Zero-dimming (SPIKE, decision #10)

**Files:** `FloatingItemPanel.swift` (and possibly `ItemWindowHost`/renderer root for the env attempt).

- [ ] **Attempt A:** wrap the hosted root in `.environment(\.controlActiveState, .active)`. If it does not compile (get-only), delete and go to B.
- [ ] **Attempt B:** on `FloatingItemPanel`, force active appearance while visible (e.g. override `isKeyWindow`/`isMainWindow`, or set the content view’s effective appearance) so SwiftUI renders `.active`. Watch for first-responder/focus side effects.
- [ ] **Fallback:** if neither is clean, stop — T1 already hides the traffic lights + uses a non-greying ✕. Document the residual.
- [ ] **Verify:** compile green + non-zero tests. **Runtime (Nathan):** click between main window and panel — accents/selection/chips must not grey. This is the one task where the outcome is decided by your build, not the compiler.
- [ ] **Commit:** `feat(item-window): keep panel content active on click-off` (or `docs: record dimming spike outcome` if fallback).

#### T3 — Body fills the fixed frame

**Files:** `ItemWindowRenderer.swift`.

- [ ] Remove `bodyZone`’s `.frame(height: Self.bodyHeight)` (line 274) → `.frame(maxWidth:.infinity, maxHeight:.infinity)`; delete the now-dead `bodyHeight` constant + its doc. Give `mainColumn`’s VStack `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)` so the body fills the remaining fixed height. Keep the 6pt gaps + `quaternarySystemFill` + counter.
- [ ] **Verify:** compile + tests. **Runtime:** body fills both inspector states; counter pinned bottom-right; no dead gap above the footer.
- [ ] **Commit:** `feat(item-window): body fills the fixed frame`

#### T4 — Property-bar placeholder mode (decision #5)

**Files:** `PropertyFieldBar.swift`, `ItemWindowRenderer.swift`.

- [ ] **PropertyFieldBar:** when `segments(...)` is empty, render placeholder cells in the SAME `SegmentedTrackLayout` (reuse the track/divider chrome): N plain `Text("Label").font(.callout).foregroundStyle(.secondary)` + M grey pill cells (`Capsule().fill(Color(.systemFill))` + `Text("Label")`). Placeholder cells are inert (no Button/popover). Default 3+3 (decision #5).
- [ ] **Renderer:** the bar is currently gated by `hasPinnedFieldProperties` (line 125) AND self-collapses internally (line 44) — change BOTH so the bar always renders (real segments when present, placeholders when empty). Preserve the symmetric 6pt gaps (the `else { Spacer(height: sm) }` branch is removed since the bar always shows).
- [ ] **Test (unit):** the placeholder-vs-real decision is `segments(...).isEmpty` — add a `PropertyFieldBar.segments` test (no coverage today): empty type → `[]`; a type with a promoted select → non-empty. (Pure static fn.)
- [ ] **Verify:** compile + non-zero tests (incl. the new one). **Runtime:** bar shows placeholder “Label” cells (plain + pills) with an undefined template.
- [ ] **Commit:** `feat(item-window): property bar placeholder Label segments`

#### T5 — Inspector → unified hairline menu (decisions #4, #6, #7, #8)

**Files:** `ItemInspector.swift` (full rewrite), possibly `PropertyEditorRow.swift` (leading icon for property rows).

- [ ] Replace `Form { itemSection; tiersSection; propertiesSection; deleteSection }.formStyle(.grouped)` with: `ScrollView { VStack(spacing:0) { contexts ; properties } }.safeAreaInset(edge:.bottom) { deleteFooter }`. Keep `.confirmationDialog` + `@State showDeleteConfirm` + the `Task { await vm.confirmDelete(); …close(ref) }` flow EXACTLY (load-bearing).
- [ ] **Shared row shell** (decision #7):
  ```swift
  private func inspectorRow(icon: String, label: String, @ViewBuilder editor: () -> some View) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: PUI.Spacing.md) {
          Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
          Text(label).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          editor()
      }
      .padding(.vertical, 6).padding(.horizontal, 12)
  }
  ```
  Between rows: `Divider().padding(.horizontal, 12)` (PropertyPanel pattern, verified).
- [ ] **Contexts group:** carry the tier icon — extend `TierEntry` with `icon` from `def.displayIcon` (verified: `BuiltInContextLinkProperties` sets `building.2`/`tag`/`briefcase`; current `TierEntry` drops it). Each tier row: `inspectorRow(icon: entry.icon, label: entry.label) { ContextValueEditor(ids: tierBinding(level), scope:.contextTier(level), index:, resolver:) }`. `ContextValueEditor` already supplies the “⊕ Add” empty state (decision #6).
- [ ] **Properties group:** `inspectorRow(icon: def.displayIcon, label: def.name) { PropertyEditorRow(definition: def, value: propertyBinding(def.id), index:, relationDisplay:, showsName: false) }` over `propertyRowDefinitions`; keep `addPropertyMenu` after the last property row. Small top gap before the first property row to separate the groups (decision #4).
- [ ] **Delete footer:** `Text("Delete").foregroundStyle(.red)` as a `Button`(plain) aligned bottom-right, sets `showDeleteConfirm = true`.
- [ ] **Drop** `itemSection` entirely (no meta).
- [ ] **Verify:** compile + non-zero tests (VM untouched; existing tests still pass). **Runtime:** unified hairline menu, contexts→properties, no headers/meta, icons present, Delete pinned bottom-right, native glass, flush-top, scrolls with many properties.
- [ ] **Commit:** `feat(item-window): unified hairline inspector (contexts→properties, bottom-right Delete)`

#### T6 — Select/status apply-on-click fix (isolated to PropertyEditorRow)

**Files:** `PropertyEditorRow.swift` only (verified: fixing here repairs Item inspector + Pages inspector + PropertiesPulldown + PropertyPanel; `PropertyFieldBar` + `PropertyCellEditor` already use the correct pattern).

- [ ] Add `@State private var statusEditorOpen = false` (beside `dateEditorOpen`).
- [ ] Rewrite `statusEditor` to mirror `dateEditor` (verified template, lines 87-109) and `PropertyCellEditor.statusEditor` (verified correct, lines 311-321): a `Button` whose label is the **collapsed current value** — `opts.first { $0.id == current }` → `PropertyChip(label:color:size:.compact)`; empty (`nil`/`""`) → a secondary placeholder pill (e.g. `.fieldBackground()` “Empty”, matching dateEditor). `.popover(isPresented:$statusEditorOpen, arrowEdge:.bottom) { ChipDropdown(options:.constant(opts), selectionMode:.single, selectedIDs:…, onPick: { value = .status($0.id); statusEditorOpen = false }, size:.compact).presentationBackground(.clear) }`.
- [ ] Leave `selectEditor` (native `Picker`, applies-on-click correctly) and `multiSelectEditor` (`MultiSelectChips`, legitimately shows toggles) — both verified fine. Do NOT scope-creep.
- [ ] **Verify:** compile + non-zero tests (no new VM logic; the write path is unchanged). **Runtime:** Status shows one collapsed pill; click → dropdown; pick → applies + closes. Confirm it’s fixed in the Pages inspector too (same component).
- [ ] **Commit:** `fix(properties): status editor applies on click (collapsed trigger + popover)`

#### T7 — Verify + Nathan real-build review

- [ ] Background builder: full compile green + non-zero `ItemWindowViewModelTests`.
- [ ] **Nathan real-build review** (the true gate for everything runtime): fixed size · zero dimming (T2 outcome) · ✕ + chrome · body fill · property-bar placeholder · unified inspector · status apply-on-click · multiple panels · drag · non-activating focus.
- [ ] Address review findings as fast-follow commits.

#### Phase F — tests + format + docs + merge (after sign-off)

- [ ] Full `-only-testing:PommoraTests` green.
- [ ] `swift format format --in-place` + `swift format lint --strict --recursive` (quirk #11).
- [ ] Docs: update stale `Features/Items.md` § Item Window (it still describes `PreviewWindow`/`.plain`/pinned-chips); add `History.md` entry; resolve Handoff Fix Log #9 (cap-comment).
- [ ] Merge `itemsv2-interactive-window` → `main`.

### Self-review

- **Spec coverage:** T1–T6 map 1:1 to the locked spec’s sweep (panel/chrome → T1, dimming → T2, body → T3, bar placeholder → T4, inspector → T5, select bug → T6); Phase F unchanged. ✓
- **Type consistency:** `inspectorRow(icon:label:editor:)` used by both groups; `TierEntry` gains `icon`; `statusEditorOpen` mirrors `dateEditorOpen`. No invented types/signatures. ✓
- **Placeholders:** none — every task names exact files + change points + verify + commit. Code shown where a decision is load-bearing; mechanical edits are pinned by line reference. ✓
- **Risk concentration:** T2 (dimming) is the only unproven mechanism → explicitly a spike with a fallback that still ships. T5 is the largest rewrite → VM untouched, so existing tests remain the regression net + the delete flow is copied verbatim.
