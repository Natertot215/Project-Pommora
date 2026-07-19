## Cards View — Implementation Plan (V2)

> **Status:** V2 — round-1 adversarial review (grounding+coverage · over-engineering+sequencing) folded; re-review pending. Realizes the ratified [[Cards View — Decision Log]] + the [[Cards View — Implementation Planning Checklist]]. Executed inline against the `cards-view` branch.

**Goal:** Take the visuals-first Cards prototype to a hardened, complete renderer — the ratified deferred features built, the audit's residual fixes closed, the full quality-gate slate run.

**Architecture:** The prototype stands (audit: harden-in-place, zero rebuild-class findings). Work is additive; each feature reuses an existing seam — the table's `cellMenu` value menu, the `window.nexus.*Menu` native-menu IPC, the resolve pipeline, the drag engine, the design-system tokens — never a parallel cards-local copy. Phases run smallest/safest → main-process → styling → gates; **each seam's unit test rides the phase that authors it**, not the end.

**Tech Stack:** React 19 + TypeScript renderer · Zustand · Electron 42 main (native menus, fs) · Vitest.

### Global Constraints

- **Only type gate:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck`; tests `npx vitest run`; build `env -u ELECTRON_RUN_AS_NODE npm run build`. From `Pommora/`. Read the summary line (`set -o pipefail`).
- **Biome formats on write** — never hand-format.
- **Main owns fs; renderer never touches Node.** Native menus / persistence go through a `{ ok }` IPC envelope.
- **Reuse over reinvent; DRY to existing tokens.** New view keys carry `.catch(undefined)` codec discipline in `shared/views.ts` (a bare enum is the D-4 view-drop landmine).
- **Ground before coding:** each cited precedent is a hypothesis until its `file:line` is read.
- Each task ends green (typecheck + vitest, its own test included) and commits with explicit paths before the next.

### Prerequisites — DONE (context)

Open-In honored in cards (`6ddc57b8`); tab-strip overflow scroll (pre-existing); tab-label overflow on the sidebar's OverflowScroll mechanism (`c7542ca2`); the 2 MED audit fixes (`28bf3f04`); the persistent thumbnail cache (`81ab02d7`).

---

### Phase 1 — Prototype hardening

**Task 1.1 — `card_size` non-finite guard.** `shared/views.ts` (`card_size` codec ~`:264`) + `views.test.ts`. Add `.refine(Number.isFinite)` so a hand-edited `1e400` resolves to `undefined` (falls to 1×) not `Infinity`. Test: decode `{card_size:1e400}` → `undefined`. Co-located test. Gate.

**Task 1.2 — manual-order read gap (extract + test).** Extract the `manualOrder` read (`CardsView.tsx:~132`, a component closure) to a pure module fn `resolveManualOrder(view, manualOverride, viewOrders)` in a `Cards/cardsOrder.ts`; read `viewOrders[view.id]` whenever it exists (cards only write it, so an unsorted+ungrouped view drops its order today — legacy/hand-edit safety). Test the pure fn. Gate. *(The extraction is what makes this — and the reorder math in Phase 5 — unit-testable; Task 8.1's promised seams are closures today, so extraction is a real step, not a footnote.)*

*(The old Task 1.3 "shared value-click hook" is dropped — the left-click dispatch and the right-click `cellMenu` are separate matrices sharing only already-shared leaves; a hook would couple cards+table for consumers that don't exist yet. Revisit as a pure gesture-descriptor only when List/Gallery prove the shape.)*

### Phase 2 — Value interaction + heading "+"

**Task 2.1 — Right-click value context menu.** `CardValue.tsx` (`onContextMenu`). **Renderer-side only** — reuse the existing `window.nexus.cellMenu` IPC + `cellMenuContextFor` + `cellMenuModel` (`@shared/cellMenu.ts`); no new main-process code. Mirror the table's *sparse, kind-specific* matrix (`TableView.tsx:132-151` — e.g. select/multi/context = clear-only-when-filled, no menu when empty; status/datetime = style-only; url = link Edit/Remove), not a uniform triple. The `style:*` actions need a `column_styles` writer cards lack today — add a small `setColumnStyle(view, colId, patch)` (via `saveView`), since `commitValue` is value-only. Test the menu-context→action mapping. Gate.

**Task 2.2 — Add-picker value panes for the non-chip kinds.** `CardAddPicker.tsx` — widen `ADDABLE_TYPES`; add Date (CalendarPicker), Number (PropertyEditor numeric), URL (PropertyEditor+validate), Checkbox (toggle) panes, mirroring `CardValue`'s editing surfaces. Order by **[Open Decision A]**. Test each pane's commit shape. Gate.

**Task 2.3 — Heading "+" on structural bands (ratified Core, I-2/I-7 — was missing).** `CardsView.tsx` band-head (`:253`, collapse-only today). Add the hover-"+" mirroring `GroupHeader.tsx:207` → create-page-in-set; **inactive on property buckets** (I-2). Test the create routing. Gate.

### Phase 3 — Native menus (one main-process batch; needs a dev-restart)

**Task 3.1 — Native right-click "Add Property" menu on the card.** `main/index.ts` (a `cards:addPropertyMenu` handler mirroring `nexus:iconMenu`/`titleMenu`/`cell-menu`, `:1918-2032`), `preload/index.ts` (bridge), `CardsView.tsx` (`onContextMenu` → invoke → route). Descriptor-in / action-out `{ok}` envelope. Separate from the in-app add-picker (checklist Don't-Forget). Include the card's Rename / Change Icon / Delete. Test the pure menu-descriptor. Gate + restart smoke.

**Task 3.2 — Retire the `viewFormatMenu` orphan (J-6).** Delete `src/main/viewFormatMenu.ts` (the standalone file) + its `main/index.ts` handler + the `preload` bridge; grep-confirm no renderer caller first. **Keep the `ViewFormat` type** (`views.ts:147`) — it's load-bearing for cards Standard/Compact. Gate.

### Phase 4 — Sort-by-Location (respec — E-4)

**Task 4.1 — a new resolve MODE, not a sort criterion.** The Sorting pane is criterion-only (`sortTargets` → `pickPrimary` writes a `SortCriterion`, `SortingPane.tsx:89,162`), and E-4 forbids Location as a criterion. So:
- **State:** a new persisted `SavedView` field (e.g. `flatten: boolean`) in `shared/views.ts`, with `.catch(undefined)` codec. Not `view.sort` (criterion-only), not `structural_order_mode` (that's band-order-under-grouping, `resolveView.ts:35`).
- **Pane:** a mode **toggle** row (not a `sortTargets` entry); reconcile the None/Order/Sub-Sort/preview UI (`SortingPane.tsx:249-306`) which branches on a primary criterion. **[Confirm with Nathan]** how location-flatten coexists with an active property sort/grouping (E-4 implies it replaces them).
- **Resolve:** COMPOSE, don't mutate — a thin wrapper that concatenates `structuralFlat`'s per-set bands into one `ungrouped` group when `flatten` is on (`structuralFlat` is now on every cards resolve — `CardsView.tsx:139` — so don't branch inside it).
- **Render:** a headerless path in `CardsView.tsx` — today the band-head renders unconditionally (`:253`); suppress it in flatten mode.
- **Drag gate:** wire `flatten` into `sortedOrGrouped` (`CardsView.tsx:132`) so manual order still persists in this mode (else the Task-1.2 read-gap recurs).
- Files: `shared/views.ts`, `pipeline/resolveView.ts` (+ a wrapper in `group.ts`), `SortingPane.tsx`, `CardsView.tsx`. Tests: the flatten wrapper (`group.test.ts`) + codec (`views.test.ts`). Gate.

### Phase 5 — Set-Card drag

**Task 5.1 — Set-Card drag/reorder.** `CardsView.tsx` `SetCard` → wrap in the drag engine like `PageCard`; the drop writes the sets' real order (filesystem semantics — **ground the exact set-reorder mechanism** the sidebar/table use before coding; confirm sets are reorderable). Scope-in per Nathan (the log had Set Cards as navigation-only, F-2 — this is a deliberate, simple expansion). Extract the reorder math to `cardsOrder.ts` + test. Gate.

*(In-gallery band-order authoring — the old Task 5.2 — is DEFERRED to the band-kit follow-up with the Prospects: it's ratified-deferred by I-7/E-8, needs band-drag groundwork, and its `group_order` write has a full-tree-vs-top-level trap. Not in this plan.)*

### Phase 6 — Per-type default view icon

**Task 6.1 — mint/type-switch (Decision B resolved → contained option).** There's no single resolution seam (`mintBase` bakes `icon:'table'` `views.ts:305`; readers are scattered `iconNameOr(view.icon,'table')`; `TYPE_GLYPH` is local to `ViewSettings.tsx:38`). So set the type glyph at **mint**, and on `setType` re-icon **when `icon === TYPE_GLYPH[oldType]`** (else keep the custom). Explicitly migrate the **legacy `icon:'table'`** value (every view minted so far stores it literally, so it must be treated as "default, re-iconable," not custom). Relocate `TYPE_GLYPH` to shared if `setType` needs it. Test the mint + type-switch icon logic. Gate.

### Phase 7 — Compact styling

**Task 7.1 — build, then STOP for sign-off.** `CardsView.css` `.is-compact` + flow packing + `--chip-zoom`/`--chip-pad-x`. Build a first pass, CDP-screenshot, **present to Nathan before finalizing.** **[Gate: Nathan's sign-off]**.

### Phase 8 — Close-out gates

**8.1 — Test sweep-up:** confirm the extracted seams (`resolveManualOrder`, the flatten wrapper, Set-Card reorder math, `locFor`, `commitValue` router, add-picker filter) are all covered; extract any still-a-closure and cover it. (Most tests ride their phase; this is the net.)
**8.2 — code-simplifier** over the whole cards diff.
**8.3 — build-breaking** adversarial review of the hardened build.
**8.4 — post-functional UIX review** of the real surface (mandatory).
**8.5 — a11y** — replace the `biome-ignore noStaticElementInteractions` stubs with roles/keyboard on card, value, zone, breadcrumb.
**8.6 — Docs** — a Cards `Features/` doc; reconcile `Views.md`'s "only Table draws"; list the cards keys in the `views.ts` parity header.

### Sequencing & Parallelism

Order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. **Serialize anything touching CardsView's drag/order machinery** — Phase 4 (flatten mode) and Phase 5 (Set-Card drag) both touch order/`manualOrder` state, so never run them as concurrent implementers on one tree. Genuinely disjoint work may overlap (6.1 icon vs 2.2 add-panes). Phase 3 is the single main-process batch (one dev-restart). Tests co-locate with their phase; Phase 8 is the sweep + non-code gates.

### Out of this plan (Prospects — deferred, per the log)

In-gallery band-order authoring / band drag · native band-header menu · inline band rename · cross-group card drag · file-property covers · Fit-Image (contain/fill) · Set-Card view previews.

### Open Decisions

- **A** — add-first kind priority (Date/Number/URL/Checkbox — Task 2.2).
- **`hideLocation` + no-properties card** (checklist #3, restored): with `hideLocation` on and no properties, a card's only add surface is the empty text-area click (no breadcrumb, no property zone — `PageCard` gates the body on `hasProps` `:537`, the loc-zone on `crumbs.length>0` `:549`). Acceptable, or an explicit "+" affordance on empty cards?
- **Location-flatten coexistence** (Task 4.1) — does it replace an active property sort/grouping, or compose?
- **Compact styling** — the sign-off gate (Task 7.1).
- *(Decision B — per-type icon — resolved above: mint/type-switch.)*

### Self-Review (V2)

- **Scope boundary corrected:** Phase 5 is now Set-Card drag only (Nathan's scope-in); band-order authoring moved to Prospects. The "Prospects excluded" claim is now true.
- **Coverage:** the previously-missing ratified Core interaction (heading "+", Task 2.3) is added; Sort-by-Location respec'd with its real state model + files; the dropped Open Decision restored.
- **Tests ride their phase** (extraction steps named), not deferred to the end.
- **Round-1 findings folded:** premature hook dropped (F2); test placement fixed (F3); Sort-by-Location respec'd (F4/Finding 1); parallelism corrected (F5); icon → mint/type-switch + legacy handling (F6); `cellMenu` reused renderer-side + `column_styles` writer named (F7/Finding 7); `viewFormatMenu.ts` file + `ViewFormat` type (Finding 6). Re-review pending.
