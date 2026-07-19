## Cards View — Implementation Plan (V3)

> **Status:** V3 — two adversarial review rounds folded (round 1: scope boundary + Sort-by-Location; round 2: flatten-mode gaps + fold-drift). Round-3 confirmation pending. Realizes the ratified [[Cards View — Decision Log]] + the [[Cards View — Implementation Planning Checklist]]. Executed inline against the `cards-view` branch.

**Goal:** Take the visuals-first Cards prototype to a hardened, complete renderer — the ratified deferred features built, the audit's residual fixes closed, the full quality-gate slate run.

**Architecture:** The prototype stands (audit: harden-in-place). Work is additive; each feature reuses an existing seam — the table's `cellMenu`, the `window.nexus.*Menu` native-menu IPC, the resolve pipeline, the `moveSet` reorder path, the design-system tokens — never a parallel cards-local copy. Phases run smallest/safest → main-process → styling → gates; **each seam's unit test rides the phase that authors it.**

**Tech Stack:** React 19 + TypeScript renderer · Zustand · Electron 42 main · Vitest.

### Global Constraints

- **Only type gate:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck`; tests `npx vitest run`; build `… npm run build`. From `Pommora/`. Read the summary line (`set -o pipefail`).
- **Biome formats on write** — never hand-format.
- **Main owns fs; renderer never touches Node.** `src/shared` is the no-fs/no-React contract — never move a renderer type (e.g. `IconName`) into it.
- **Reuse over reinvent; DRY.** New view keys carry `.catch(undefined)` codec discipline in `shared/views.ts`.
- **Ground before coding:** each cited precedent is a hypothesis until its `file:line` is read.
- Each task ends green (typecheck + vitest, its own test) and commits with explicit paths.

### Prerequisites — DONE

Open-In in cards (`6ddc57b8`); tab-strip scroll (pre-existing); tab-label overflow on the sidebar's OverflowScroll (`c7542ca2`); the 2 MED audit fixes (`28bf3f04`); the persistent thumbnail cache (`81ab02d7`).

---

### Phase 1 — Prototype hardening

**Task 1.1 — `card_size` non-finite guard.** `shared/views.ts` (`card_size` codec ~`:264`) + `views.test.ts`. Add `.refine(Number.isFinite)` (`.catch(undefined)` already swallows the fail → 1×). Test: `{card_size:1e400}` → `undefined`. Gate.

**Task 1.2 — manual-order read gap (extract + test).** Extract the `manualOrder` read (`CardsView.tsx:~132`, a closure) to a pure `Cards/cardsOrder.ts` fn: `resolveManualOrder(sortedOrGrouped: boolean, manualOverride: string[] | null, viewOrders: string[] | undefined)` — the gate needs `sortedOrGrouped` (`= sortKeys>0 || view.group!=null`), so it's an input, not re-derived inside. Read `viewOrders[view.id]` whenever it exists. Test the pure fn. Gate. *(This extraction is what makes the order seams unit-testable; the reorder math in Phase 5 extracts here too.)*

### Phase 2 — Value interaction + heading "+"

**Task 2.1 — Right-click value context menu.** `CardValue.tsx` (`onContextMenu`). Renderer-side only — reuse `window.nexus.cellMenu` (generic, `TableView.tsx:965`) + `cellMenuModel` (`@shared/cellMenu.ts`). **`cellMenuContextFor` is private in `TableView.tsx:132` — lift it to a shared module first**, then both consume it. Mirror the table's *sparse, kind-specific* matrix (`:132-151`), not a uniform triple. The `style:*` actions need a `column_styles` writer cards lack — add `setColumnStyle(view, colId, patch)` via `saveView` (note: no live `styleOverride` preview like the table's `:582`, so a style change flashes through a `load()` round-trip — acceptable for v1). Test the menu-context→action mapping. Gate.

**Task 2.2 — Add-picker value panes (non-chip kinds).** `CardAddPicker.tsx` — widen `ADDABLE_TYPES`; add Date/Number/URL/Checkbox panes mirroring `CardValue`'s editing surfaces. Order by **[Open Decision A]**. Test each pane's commit shape. Gate.

**Task 2.3 — Heading "+" on structural bands — VISUAL + GATING ONLY (I-2).** `CardsView.tsx` band-head (`:253`). Add the hover-"+" button, structural-set-only (inactive on property buckets), **mirroring the table's `GroupHeader.tsx:199-209` — which is deliberately INERT** (no `onClick`, "pending Nathan's creation-affordance design Q-7/Q-9"). So build the button + gating to match; the **create-page-in-set routing is a deferred design decision** (Open Decisions), NOT built here — I-2 ratifies the "+" *exists* on structural headings, not its behavior. Test the gating (renders on structural, absent on property/ungrouped). Gate.

### Phase 3 — Native menus (one main-process batch; dev-restart)

**Task 3.1 — Native right-click "Add Property" menu on the card.** `main/index.ts` (`cards:addPropertyMenu`, mirroring `nexus:iconMenu`/`titleMenu`/`cell-menu` `:1918-2032`), `preload/index.ts` bridge, `CardsView.tsx` (`onContextMenu` → invoke → route). Descriptor-in / action-out `{ok}` envelope; separate from the in-app picker; include card Rename/Change Icon/Delete. Test the pure descriptor. Gate + restart smoke.

**Task 3.2 — Retire the `viewFormatMenu` orphan (J-6).** Delete `src/main/viewFormatMenu.ts` + its `main/index.ts` handler (`:164`) + `preload` bridge (`:147`); grep-confirm no renderer caller. **Keep the `ViewFormat` type** (`views.ts:147`, load-bearing for cards Standard/Compact). Gate.

### Phase 4 — Sort-by-Location (a resolve MODE — E-4)

**Task 4.1 —** a computed location order, not a criterion:
- **State:** a new persisted `SavedView` boolean, **named `location_flatten`** (NOT `flatten` — collides with `flattenStructural`/`flattenGroups`/`flattenContainer`), `.optional()` in `shared/views.ts` (a boolean isn't the D-4 enum-drop landmine, but keep the sibling discipline).
- **Resolve — forces structural.** `resolveGroups` routes to `property()` when `view.group` is a resolvable property group (`group.ts:435`), which would flatten *property-sort* order and violate E-4. So `location_flatten` **forces structural resolution (bypasses `view.group`)** to preserve filesystem order. Compose (don't mutate `structuralFlat`): a thin wrapper concatenates its per-set bands' items into one `UNGROUPED` group when on.
- **Render — headerless + force-open.** Suppress the band-head in flatten mode; **and force `Reveal open`** — the composed band keys `UNGROUPED`, which is *also* the container heading band's key (`group.ts:238`, `types.ts:518`), so a collapsed-`_ungrouped` state from structural mode would otherwise hide every card with no head to toggle (round-2 #1).
- **Drag — DISABLED in flatten mode.** Location order is computed; a cross-location drop is a `movePage` (the deferred cross-group Prospect), and `manualOrder` is a within-band tiebreaker (`sort.ts:174`) that would silently snap a cross-location drag back (round-2 #2). So disable `SortableZone` when `location_flatten` is on — don't wire it into the drag gate.
- **Pane:** a mode **toggle** row (not a `sortTargets` criterion). Reconcile the None/Order/preview UI (`SortingPane.tsx:249-306`); flatten + a property group are **mutually exclusive** in the UI (flatten wins). Watch-item: the "Sort By: None" summary reads oddly while flatten is on — cosmetic.
- Files: `shared/views.ts`, `pipeline/resolveView.ts` (+ wrapper in `group.ts`), `SortingPane.tsx`, `CardsView.tsx`. Tests: the flatten wrapper (`group.test.ts`) + codec. Gate.

### Phase 5 — Set-Card drag

**Task 5.1 — Set-Card drag/reorder.** `CardsView.tsx` `SetCard` → wrap in the drag engine like `PageCard`; on drop dispatch **`moveSet`** (the confirmed mechanism: `mutate.ts:531` writes `set_order` `schemas.ts:51`; the sidebar does this at `sidebarDnd.tsx:259`). Add the `!isDragging` guard to `SetCard.onClick` (`:321`, like `PageCard:505`) so a drag-drop doesn't navigate. Note: `moveSet`→`load` may flash (no optimistic reorder) — acceptable for v1. Extract the reorder math to `cardsOrder.ts` + test. Gate.

*(In-gallery band-order authoring — deferred to Prospects: ratified-deferred I-7/E-8, needs band-drag groundwork, `group_order` full-tree trap.)*

### Phase 6 — Per-type default view icon

**Task 6.1 — mint/type-switch (Decision B resolved).** `mintBase` bakes `icon:'table'` (`views.ts:305`); `setType` is **co-located with `TYPE_GLYPH`** (`ViewSettings.tsx:38,118`) — **no relocation** (moving `TYPE_GLYPH: Record<ViewType,IconName>` to `shared` would drag a renderer type into the contract — a Hard Rule violation, and `setType` doesn't need it relocated). On `setType`, re-icon **when `icon === TYPE_GLYPH[oldType]`** (else keep the custom) — this covers the legacy `icon:'table'` value for free (`'table' === TYPE_GLYPH['table']`). **Also migrate the second documented legacy value `'tablecells'`** (`views.ts:301`) — it's `!== TYPE_GLYPH['table']`, so widen the check to both legacy values. Test the mint + type-switch logic. Gate.

### Phase 7 — Compact styling

**Task 7.1 — build, then STOP for sign-off.** `CardsView.css` `.is-compact` + flow packing. Build a first pass, CDP-screenshot, **present to Nathan before finalizing.** **[Gate: sign-off]**.

### Phase 8 — Close-out gates

**8.1 — Test sweep-up:** confirm the extracted seams (`resolveManualOrder`, the flatten wrapper, Set-Card reorder math, `locFor`, `commitValue` router, add-picker filter) are covered; extract + cover any still-a-closure. **8.2** code-simplifier over the diff. **8.3** build-breaking review of the hardened build. **8.4** post-functional UIX review (mandatory). **8.5** a11y — replace the `biome-ignore noStaticElementInteractions` stubs with roles/keyboard. **8.6** docs — a Cards `Features/` doc; reconcile `Views.md`; list the cards keys in the `views.ts` parity header.

### Sequencing & Parallelism

Order 1→8. **Serialize anything touching CardsView drag/order** (Phase 4 flatten + Phase 5 Set-Card drag both touch order state) — never concurrent implementers on one tree. Disjoint work may overlap (6.1 icon vs 2.2 add-panes). Phase 3 is the one main-process batch. Tests co-locate with their phase.

### Out of this plan (Prospects — deferred, per the log)

In-gallery band-order authoring / band drag · native band-header menu · inline band rename · cross-group card drag (`movePage`) · file-property covers · Fit-Image · Set-Card view previews.

### Open Decisions

- **A** — add-first kind priority (Date/Number/URL/Checkbox — Task 2.2).
- **Heading-"+" create routing** (Task 2.3) — the table's "+" is an inert stub pending your creation-affordance design (Q-7/Q-9). Cards' "+" ships inert-matching v1; when you design the create flow, both light up together. Your call whether to design it now or keep it inert.
- **`hideLocation` + no-properties card** (checklist #3): with `hideLocation` on and no properties, a card's only add surface is the empty text-area click. Acceptable, or an explicit "+" affordance on empty cards?
- **Compact styling** — the sign-off gate (Task 7.1).
- *(Resolved: Decision B → mint/type-switch. Location-flatten coexistence → flatten forces structural, mutually exclusive with property grouping.)*

### Self-Review (V3)

- **Round-2 folds:** collapse collision → force-open in flatten (#1); cross-location drag → disabled in flatten (#2); heading-"+" → visual+gating only, create routing deferred (#3); compose coexistence → flatten forces structural (#4); dropped the TYPE_GLYPH relocation (#5); widened legacy icon to `tablecells` (#6); `resolveManualOrder` signature takes `sortedOrGrouped` (#7); lift the private `cellMenuContextFor` (#8); `flatten`→`location_flatten` rename; Set-Card `!isDragging` guard.
- **Coverage:** every ratified Core has a task (heading-"+" visual now included); every deferred item explicitly parked; no plan↔log contradiction. Set-Card drag feasibility verified (`moveSet`/`set_order`).
- **Round-3 confirmation pending;** if clean → ratify.
