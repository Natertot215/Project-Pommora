## Cards View — Implementation Plan

> **Status:** written, pending adversarial review (not yet ratified). Realizes the ratified [[Cards View — Decision Log]] + the [[Cards View — Implementation Planning Checklist]]. Executed inline against the `cards-view` branch.

**Goal:** Take the visuals-first Cards prototype to a hardened, complete renderer — every deferred feature built, the audit's residual fixes closed, and the full quality-gate slate run.

**Architecture:** The prototype stands (audit verdict: harden-in-place, zero rebuild-class findings). Work is additive: each deferred feature reuses an existing seam — the table's value-menu + cell leaves, the `window.nexus.*Menu` native-menu IPC, the resolve pipeline, the drag engine, the design-system tokens — rather than inventing a parallel mechanism. Phases are ordered by dependency and blast radius: the smallest/safest fixes first, the main-process work mid, styling + gates last.

**Tech Stack:** React 19 + TypeScript renderer · Zustand · Electron 42 main (native menus, fs) · CodeMirror 6 (page previews) · Vitest.

### Global Constraints

- **Only type gate:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck`; tests `npx vitest run`; build `env -u ELECTRON_RUN_AS_NODE npm run build`. From `Pommora/`. Read the summary line — piped exit codes lie (`set -o pipefail`).
- **Biome formats on write** — never hand-format; an edit failing on whitespace means it reformatted, re-read and retry.
- **Main owns fs; the renderer never touches Node.** Every native menu / persistence goes through a `{ ok }` IPC envelope in the preload bridge.
- **Reuse over reinvent** — mirror the table's mechanism (cited per task) instead of a cards-local copy; DRY to existing tokens.
- **`src/shared/types.ts` is the cross-process contract.** New view keys carry `.catch(undefined)` codec discipline in `shared/views.ts`.
- **Dev app runs against the real Nexus** — drive the editor only on throwaway pages.
- Each task ends green (typecheck + vitest) and is committed with explicit paths before the next.

### Prerequisites — DONE (context, not tasks)

Cards honor per-collection Open In (`6ddc57b8`); tab-strip overflow scroll (pre-existing); individual tab-label hover eclipse-scroll (`a8ebc429`). The two MED audit fixes shipped (`28bf3f04`); the persistent thumbnail cache shipped (`81ab02d7`).

---

### Phase 1 — Prototype hardening (the audit's 3 LOWs)

Smallest, safest, no new surface. Clears the residual before feature work builds on it.

**Task 1.1 — `card_size` non-finite guard.**
- File: `src/shared/views.ts` (the `card_size` codec, ~`:264`). Test: `shared/views.test.ts`.
- Approach: the codec is `union([number, enum→factor]).optional().catch(undefined)`. Add `.refine(Number.isFinite)` (or clamp to `[SCALE_MIN, SCALE_MAX]` on read) so a hand-edited `1e400` can't become `--card-scale: Infinity` → invalid grid track.
- Test: decode `{ card_size: 1e400 }` → resolves to `undefined` (falls back to 1×), not `Infinity`. Gate.

**Task 1.2 — manual-order read gap.**
- File: `src/renderer/src/Detail/Views/Cards/CardsView.tsx` (`manualOrder`, ~`:131`).
- Approach: cards only ever *write* `viewOrders`, so an unsorted + ungrouped view (no `group` key) drops its persisted drag order on reopen (the read is gated on `sortedOrGrouped || manualOverride`). Read `viewOrders[view.id]` whenever it exists. No in-app path produces `group === undefined` today, so this is legacy/hand-edit safety — fold it in, low risk.
- Test: cover in the CardsView pure-logic tests added in Phase 8 (or a focused unit if extracted). Gate.

**Task 1.3 — DRY-extract the CardValue click-matrix.**
- Files: extract from `src/renderer/src/Detail/Views/Cards/CardValue.tsx` (`onClick`, `:52-82`) + `TableView.tsx` (`onCellClick`) → a shared `Detail/Views/PropertyEditing/useValueClick.ts` (or similar) returning the per-kind dispatch.
- Approach: the per-type click routing (status-cycle / checkbox-toggle / picker / editor / url-open) is duplicated orchestration across cards + table (the *surfaces* — Cell, PropertyPicker, PropertyEditor, CalendarPicker — are already shared). Extract the dispatch to one hook both consume, so List/Gallery reuse it and a matrix change is one edit. **Do this before Phase 2** (the right-click menus extend the same matrix).
- Test: the extracted hook gets unit coverage; table + cards behavior unchanged (full suite green). Gate.

### Phase 2 — Value interaction completion

Completes the per-value matrix the prototype half-built.

**Task 2.1 — Right-click value context menus.**
- Files: `CardValue.tsx` (add an `onContextMenu`), reusing the table's value-menu. Ground the table's value context menu first (`TableView.tsx` — the `A-13` Clear/Style/Edit-per-kind matrix) and mirror it, ideally via a shared menu builder so it isn't a third copy.
- Approach: left-click matrix is done; wire the right-click half — per kind: Clear (→ commit null), Style (the column-style submenu), Edit (open the picker/editor). Reuse the existing menu components + `commitValue` router.
- Test: unit the menu-item→action mapping. Gate.

**Task 2.2 — Add-picker value panes for the non-chip kinds.**
- Files: `src/renderer/src/Detail/Views/Cards/CardAddPicker.tsx` — widen `ADDABLE_TYPES` beyond `select/status/multi_select`; add value panes for Date (CalendarPicker), Number (PropertyEditor numeric), URL (PropertyEditor + validate), Checkbox (a toggle).
- Approach: `ValuePane` currently uses `pickSemantics` (chip kinds). Add per-kind panes mirroring `CardValue`'s editing surfaces, so first-*add* of a date/number/url/checkbox authors its value inline (editing existing values already works for all kinds).
- Ordering: build in the priority you set — **[Open Decision A]** which kind first.
- Test: unit each pane's commit shape. Gate.

### Phase 3 — Native card & property menus (main-process)

The one main-process batch. Needs a dev-process restart to test (main + preload don't HMR).

**Task 3.1 — Native right-click "Add Property" menu on the card.**
- Files: `src/main/index.ts` (a new `cards:addPropertyMenu` handler, mirroring `nexus:*Menu` / `tabMenu`), `src/preload/index.ts` (bridge entry), `CardsView.tsx` (`onContextMenu` on the card → invoke → route to the add flow).
- Approach: a real OS menu, **separate** from the in-app add-picker (PickerMenu). Right-click a card → native menu listing the page's blank properties (+ the card's own Rename / Change Icon / Delete). Reuse the container/entity menu precedents.
- Test: the handler's menu-descriptor is pure/testable; the IPC returns a `{ ok }` envelope. Gate + dev-restart smoke.

**Task 3.2 — Retire the `viewFormatMenu` IPC orphan (J-6).**
- Files: `src/main/index.ts` + `src/preload/index.ts` (remove the handler + bridge entry), any dead caller.
- Approach: superseded by the D-8 click-toggle; remove it in this main-process batch so the restart covers both. Verify no live caller first (grep).
- Test: typecheck + grep-clean. Gate.

### Phase 4 — Sort-by-Location (pipeline)

**Task 4.1 — the flatten-mode resolve + Sorting-pane entry.**
- Files: `src/renderer/src/Detail/Views/pipeline/resolveView.ts` + `group.ts` (the flatten mode); `Components/Detail/SortingPane` (the `Location` entry). Tests: `group.test.ts` / `resolveView.test.ts`.
- Approach (E-4): "Sort by Location" flattens the structural bands into **one headerless list** in filesystem order — not a `sort.ts` criterion but a resolve/render mode. This builds naturally on the `structuralFlat` variant just added (`28bf3f04`): extend it to collapse *all* top-level sets into a single ungrouped band when the location-sort mode is active. Add the `Location` option to the Sorting pane.
- Test: a nested tree + location-sort → one flat band, filesystem order, no set headers. Gate.

### Phase 5 — Drag & order

**Task 5.1 — Set-Card drag/reorder.**
- Files: `CardsView.tsx` (`SetCard` → wrap in the drag engine like `PageCard`), the reorder → filesystem semantics (`movePage`/set reorder).
- Approach: Set Cards don't drag today. Reorder is filesystem order (a set's position), so the drop writes the real order — mirror the sidebar/table set-reorder path, not the view-local `viewOrders`.
- Test: reorder writes the expected fs order. Gate.

**Task 5.2 — In-gallery band-order authoring.**
- Files: `CardsView.tsx` (band-header drag) + `group_order` write.
- Approach: today cards render whatever `group_order` holds (authored via the table). Add band drag → write `group_order`, reusing the table's band-reorder mechanism.
- Test: band drag writes `group_order`. Gate.

### Phase 6 — View chrome

**Task 6.1 — Per-type default view icon.**
- Files: `shared/views.ts` (`mintBase`, ~`:305` hardcodes `icon: 'table'`) + the icon-resolution seam. Test: `views.test.ts`.
- Approach: a view's default icon follows its type (cards → `cards-grid`, via `TYPE_GLYPH`) while a user's custom icon still overrides. Decide at the resolution seam (a fresh view with no custom icon shows its type glyph) rather than baking it at mint, so a type-switch re-icons too. **[Open Decision B]** confirm: resolution-seam vs mint/type-switch.
- Test: a minted cards view resolves the cards glyph; a custom icon wins. Gate.

### Phase 7 — Compact styling

**Task 7.1 — Compact card layout — build, then STOP for sign-off.**
- Files: `CardsView.css` (`.is-compact`, the flow packing, `--chip-zoom`/`--chip-pad-x`).
- Approach: the knobs exist; the *look* (value density, padding, flow packing) is unratified. Build a first pass, CDP-screenshot it, and **present to Nathan before finalizing** — do not close this task without sign-off. **[Gate: Nathan's sign-off]**.

### Phase 8 — Quality gates (close-out)

**Task 8.1 — CardsView test coverage.** Cover the pure/logic seams that have none: `flattenGroups`, `locFor` (the breadcrumb structural trim), `reorderInBand` (full-order write), the `commitValue` tier/property router, the add-picker addable filter, and the Task 1.2 read gap. Gate.

**Task 8.2 — code-simplifier pass** over the whole cards diff (studio rule before "done").

**Task 8.3 — build-breaking adversarial review** of the hardened build; fold findings.

**Task 8.4 — post-functional UIX review** of the real working surface (mandatory per Review-Discipline, no matter how clean).

**Task 8.5 — a11y** — replace the prototype's `biome-ignore noStaticElementInteractions` stubs with proper roles/keyboard on the card, value, zone, and breadcrumb surfaces.

**Task 8.6 — Docs** — a Cards `Features/` doc; reconcile `Views.md`'s "only Table draws" framing; list the cards keys in the `views.ts` Swift-parity header. Commit with the code.

### Sequencing Rationale

1 (hardening) is prerequisite cleanup — and 1.3's matrix extraction unblocks 2. 2 completes value interaction in the renderer. 3 is the single main-process batch (one dev-restart covers the native menu + the orphan retire). 4–6 are independent renderer/pipeline features (parallelizable). 7 gates on your eye. 8 closes out. Prospects (file-property covers, Fit-Image, cross-group drag, band chrome, Set-Card view previews) are **out of this plan** — a separate later pass.

### Open Decisions (carried from the log)

- **A** — add-first kind priority (which of Date/Number/URL/Checkbox gets its add-pane first).
- **B** — per-type default icon at the resolution seam vs mint/type-switch.
- **Compact styling** — the sign-off gate on Task 7.1.

### Self-Review

- **Coverage:** every locked-scope item maps to a task — 3 LOWs (1.1–1.3), all 8 deferred features (2.1, 2.2, 3.1, 3.2, 4.1, 5.1, 5.2, 6.1), Compact (7.1), all 6 quality gates (8.1–8.6). Prospects explicitly excluded. ✓
- **Precedent grounding:** each feature cites the seam it reuses; the mechanical tasks (right-click menu, native menu, band-order) reference the table/sidebar precedent to ground before writing, not to hand-wave. The executor grounds the exact `file:line` of each cited precedent before coding it (a doc claim is a hypothesis until the code proves it).
- **Type consistency:** new view keys carry `.catch` codec discipline; `structuralFlat` (Phase 4) is the already-shipped variant, extended not re-invented.
