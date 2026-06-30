# Table Views — Part 2 (Table UIX Redo + Label Fix) — Implementation Plan

> Spec (ratified V3): `6-29 — Table Views Part 2 — UIX Redo + Label Fix`. Execute task-by-task; each task ships a **green commit** after its gate. Decisions are referenced by id (A-1, D-5, H-2…).

**Goal:** Replace the Part-1 throwaway `TableView` stub with the real Collection/Set table — id→name resolution, type-aware cells, grouping disclosures, column/row/group drag, resize, hide/show, inline edits — designed fresh + DRY.

**Architecture:** Renderer-side resolution (one resolver fed a `{schema, contextsById, labels}` context), reusing the merged pipeline (columns/filter/group/sort/value), PommoraDND for all drag, the chip tokens for cells, and the existing per-container order seam (`page_order`/`set_order`/`setChildOrder`) + a NEW per-machine order cache for sorted nudges.

**Tech Stack:** React 19 · TypeScript · vanilla-extract (`*.css.ts`) + plain CSS · Zustand store · Vitest · PommoraDND (`interactions/drag.tsx`) · main↔renderer IPC.

## Global Constraints

- **Per-task gate (Nathan, overnight):** implement → confirm (green Vitest for logic; a headless screenshot of the **Ideas collection** for anything visual) → dispatch a **code-review agent + code-simplifier agent** → only then mark complete + commit. Verify agent output myself; never trust the banner.
- **Surface chosen values in chat** (widths, paddings, tokens) in plain language as each lands, so Nathan can redirect.
- **Colors are hex tokens**; no `rgb()`. Biome auto-formats — never hand-format / never run Biome. Typecheck (`npm run typecheck`) is the only type gate.
- **Persistence is load-bearing (H-2):** reorder/resize/hide **must** write to the right `SavedView` fields and survive hide-toggle + view-switch — the exact Swift regression. Every persistence path gets a test.
- **DRY:** one resolver, one width table, one chip component, one `selectColor→chipColor` map, one `tierLabel`; reuse the sidebar disclosure animation + existing motion tokens (no new keyframes for hide/show or disclosures).
- **Main owns fs**; renderer reaches it only via typed IPC envelopes (`{ok}|{ok:false,error}`).

## Proposed Values (redline freely)

- **Column widths** `{min, default, max}` px — Title `120/280/480`, Status `80/120/200`, Select `80/120/220`, Multi-Select `100/180/320`, Checkbox `44/60/90`, Link/url `100/180/340`, File `100/160/300`, Contexts/tier `100/170/300`, Created/Modified At `90/130/190`, Date&Time `90/140/210`, Number `70/110/180`, fallback `80/150/340`.
- **Cell padding** — X `12px` (keeps the current end-gutter, H-4); Y **Compact `4px`** (default), Standard `7px`.
- **Inter-section gaps (J-2)** — root Set disclosure `16px`, nested Sub-Set `8px`.
- **Header divider (H-6)** — segment inset `5px` top+bottom (so the hairline is shorter than the row).
- **Hide/show + disclosure motion** — the `disclosure` duration (180ms) + `--ease-standard`; chevron reuses the sidebar's.
- **Row height** — Compact `30px`, Standard `38px` (drives Y-padding + icon size).

## File Structure

```
src/shared/
  types.ts            — NexusLabels: + area/topic LabelPairs, drop sidebarSections (B)
  views.ts            — SavedView: + hide_page_icons?, hide_borders? (E-5)
src/main/
  settings.ts         — labelsToDisk: write area/topic (B-4)
  readNexus.ts        — readLabels: parse area/topic + migration (B-3/B-4)
  io/viewOrders.ts     — NEW per-machine sorted-order cache (.nexus/viewOrders.json) (D-5)
  index.ts / preload  — IPC for viewOrders get/set (D-5)
src/renderer/src/
  Detail/Views/Table/
    TableView.tsx      — the real table (rewrite the stub)
    columnLabel.ts     — resolver: id→name via {schema, labels} (A-2)
    columnWidths.ts    — per-type {min,default,max} table (I-1)
    cells/             — TitleCell, ChipCell, ContextChipCell, CheckboxCell, DateCell, UrlCell, NumberCell, ModifiedCell (G)
    GroupHeader.tsx     — disclosure header + glyphs + +button (E-4, L)
    Table.css.ts        — grid (separator.border token), padding DRY (J), size typography (K)
  Detail/Views/pipeline/
    columns.ts          — feed effective schema names (tier defs) if needed
  Components/
    Chip.tsx            — shared pill (G-3), ContextChip.tsx (G-4)
  design-system/tokens/
    chipColorMap.ts     — selectColor→chipColor (G-3)
```

---

## Phase 1 — Foundation (logic; Vitest-verified, no screenshots)

### Task 1 — NexusLabels restructure (B)

**Files:** `src/shared/types.ts`, `src/main/settings.ts`, `src/main/readNexus.ts`, sidebar label call-sites; tests `settings.test.ts` + a labels read test.
- Add `area: LabelPair`, `topic: LabelPair` to `NexusLabels`; remove `sidebarSections`. Update `DEFAULT_LABELS` (`area {Area, Areas}`, `topic {Topic, Topics}`). Sidebar headers derive: areas←`area.plural`, topics←`topic.plural`, pages←`pageCollection.plural`.
- `labelsToDisk` writes `labels.area/topic/project`. `readLabels` parses them; **migration** — absent `area`/`topic` → plural from old `sidebar_sections.{areas,topics}`, singular default "Area"/"Topic".
- **Verify:** round-trip test (write→read identity), migration test (old shape → new), sidebar still labels correctly.
- **Gate:** review + simplify. **Commit:** `feat(react/labels): tiers as first-class LabelPairs; drop sidebarSections`.

### Task 2 — `tierLabel` + `columnLabel` resolver (A-2)

**Files:** `Detail/Views/Table/columnLabel.ts` + test.
- `tierLabel(level, labels)` → `[area,topic,project][level-1].plural`. `columnLabel(columnId, schema, labels)` → reserved (`_title`→"Title", `_created_at`→"Created", `_modified_at`→"Modified", `_tierN`→tierLabel) else `schema.find(id)?.name ?? columnId`.
- **Verify:** resolves every reserved + a `prop_*` + an unknown id (falls back to id, never throws).
- **Gate** + **Commit:** `feat(react/table): renderer-side column-label resolver`.

### Task 3 — Resolution context types + `contextsById` (A-4)

**Files:** `Detail/Views/Table/resolveContext.ts` (build `{schema, contextsById, labels}` from `tree`) + test. `contextsById`: ULID→`{title, color}` from `tree.contexts.{areas,topics,projects}`.
- **Verify:** a tier ULID resolves to title+color; missing id → undefined (cell renders bare/empty, never throws).
- **Gate** + **Commit:** `feat(react/table): render resolution context`.

### Task 4 — `selectColor→chipColor` map + width table (G-3, I-1)

**Files:** `design-system/tokens/chipColorMap.ts`, `Detail/Views/Table/columnWidths.ts` + tests.
- Map all 11 Notion colors → chip palette (gray→grey, teal→cyan, brown/pink/indigo→nearest; rest 1:1). Width table = the Proposed Values; `widthFor(kind|type)` with fallback.
- **Verify:** every selectColor maps; every column type has clamped `{min,default,max}`.
- **Gate** + **Commit:** `feat(react/table): color map + per-type width table`.

### Task 5 — SavedView fields + per-machine order cache (E-5, D-5)

**Files:** `src/shared/views.ts` (+ `hide_page_icons?`, `hide_borders?`), `src/main/io/viewOrders.ts` (NEW `.nexus/viewOrders.json`, folds pattern, keyed by view id), IPC `viewOrders:get/set` in `index.ts`+`preload`, tests.
- `viewOrders` = `Record<viewId, string[]>` (the manual tiebreaker list); read/modify/write, `resolveOrder` tolerance.
- **Verify:** SavedView round-trips the new fields (loose-object foreign-key safe); viewOrders get/set round-trip; absent → `{}`.
- **Gate** + **Commit:** `feat(react/views): hide toggles + per-machine view-order cache`.

---

## Phase 2 — Render (visual; screenshot the Ideas collection per task)

### Task 6 — Table skeleton: single header + grouped sections + horizontal scroll (H-1, A, Q-4/Q-8)

**Files:** rewrite `TableView.tsx`, `Table.css.ts`. One `<thead>`-equivalent header row resolving names via `columnLabel`; grouped body sections (no per-group header repeat); `overflow-x:auto` container; grid lines ← `separator.border` token, rounded hairline caps (H-7). Plain-text cells still (type-aware cells next task) but **names resolved** (no raw ids). No-value rows = normal rows, grouped-cell empty (Q-8).
- **Verify:** screenshot Ideas — column headers + set-group headers show **names not ULIDs**; horizontal scroll when narrow.
- **Gate** (incl. screenshot) + **Commit:** `feat(react/table): real table shell — single header, resolved names, h-scroll`.

### Task 7 — Type-aware cells (G-1, G-2, N)

**Files:** `cells/*`, `Components/Chip.tsx`, `Components/ContextChip.tsx`. Title (icon+text), select/status→`<Chip>`, multi→chips (chipLabel cap), checkbox→`chipCheckbox`, url→inline link, date→stub, number→text, tier→ContextChip(s), modified/created→formatted date, file→name links. Overflow = `chipLabel` logic (ellipsis + hover-scroll, Q-4). Option `value→label` via the context.
- **Verify:** screenshot Ideas — chips, ContextChips (neutral fill, 8px), checkboxes, dates render right; long values ellipsize.
- **Gate** + **Commit:** `feat(react/table): type-aware cells (chips, ContextChips, dates)`.

### Task 8 — Disclosures + group rendering (E-4, L)

**Files:** `GroupHeader.tsx`, `Table.css.ts`. Chevron disclosure reusing the **sidebar animation**; collapse ← `collapsed_groups`; group glyphs — status→pill, checkbox→glyph+state, date→icon+bucket (callout-emphasized), select→chip; hover-revealed `label-secondary` + "+" button (calls `newItemsTo()` default 'bottom', no caller — commented). Inter-section gaps (J-2).
- **Verify:** screenshot Ideas — collapsible Set groups with chevrons; property-group glyphs; gaps.
- **Gate** + **Commit:** `feat(react/table): disclosures + group-header rendering`.

### Task 9 — Size + typography + padding DRY (J, K, H-4, H-6)

**Files:** `Table.css.ts`. Table Size Standard|Compact (default Compact) → row/disclosure typography (callout / callout-emphasized) + row height + Y-padding; X-padding 12px (keep gutter); header divider inset.
- **Verify:** screenshot — Compact density reads right.
- **Gate** + **Commit:** `feat(react/table): size + typography + padding DRY`.

---

## Phase 3 — Interaction (screenshot + persistence tests)

### Task 10 — Column reorder + ghosted drag (E-2)
PommoraDND horizontal `SortableZone` over headers → `property_order`; ghosted lifted column. **Persistence test** (H-2): reorder writes `property_order`, survives view re-read. Screenshot the drag. Commit.

### Task 11 — Column resize (H-2)
Edge-drag → `column_widths` (clamped to width table). **Persistence test**: width survives hide-toggle + view-switch. Screenshot. Commit.

### Task 12 — Column hide/show + collapse animation (E-1, E-11)
Right-click header → Hide (writes `hidden_properties`); collapse-in/expand-out on the `disclosure` token. Tiers default-on, in Visibility. **Persistence test**. Screenshot. Commit.

### Task 13 — Row drag + ghosted + ordering model (E-3, D-1…D-8)
Left-gutter hover handle, vertical `SortableZone`, ghosted row. No-sort → `page_order`; single-sort → clamp to equal-key run, write `viewOrders` cache; 2+ sort → no handle; cross-group → mutate grouped property. **Tests** per D-case. Screenshot. Commit.

### Task 14 — Group reorder (D-7)
Group-header handle → property-group `GroupConfig.order`+`order_mode:'manual'` / structural `set_order`. **Test** both homes. Screenshot. Commit.

### Task 15 — Inline edits (E-6, E-8, E-9, E-10)
Title (dbl-click empty / right-click rename), icon (right-click→IconPicker), url cell (empty→edit, filled→open/dbl-edit); commit Enter/blur, cancel Escape. Screenshot. Commit.

---

## Phase 4 — Polish

### Task 16 — Banner/title unlock (H-3)
Revert `.detail-locked` for collection/set/context via `DetailScaffold` `lockedHeader`; banner+title scroll with content. Screenshot before/after. Commit.

### Task 17 — Closeout
Full `npm run typecheck` + Vitest suite green; post-functional UIX review of the live table (mandatory per Review-Discipline); update `Features/Views.md` (Rich Table Cells → shipped) + History + Handoff; surface the final value table to Nathan.

---

## Notes

- Tasks 1–5 are pure logic → Vitest is the confirmation (nothing visual yet); screenshots begin at Task 6.
- If a task surfaces a wrong assumption, re-assess the remaining tasks before dispatching the next (per CLAUDE.md).
- Display-As toggle, the creation-affordance caller, capsule/status-as-checkbox renders, and the real date picker are **out of scope** (Part-3 / deferred per spec).
