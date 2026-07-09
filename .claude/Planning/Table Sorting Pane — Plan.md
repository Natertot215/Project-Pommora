# Table Sorting Pane — Plan

> **For agentic workers:** inline execution, task-by-task, feature branch `sort-pane`. Gates per task: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npx vitest run` + `npm run build`. Biome auto-formats on write — never run it. Commit after each task with explicit-path staging.

**Goal:** The Sort leaf (both doors — SettingsPane's Sort entry, ViewSettings' Sort leaf) authors a view's `sort[]` on the grouping pane's exact chassis: Sort By + Order, Sub-Sort + its sub-tier Order, a separator, then the example order.

**Architecture:** A `SortingPane` sibling of `GroupingPane`, built entirely from the grouping constitution: MenuPaneTopRow header, the pane-flip Reveal disclosure for Sort By, MenuItem-chassis ValueRows with trailing PickerControls, the scrollable middle region on `groupingPane.css`'s shared classes for the example order. Persistence rides `saveViewAdopting(source, view, refetch)` — no schema work, no IPC work: `SavedView.sort` (`SortCriterion { property_id, direction }`) already decodes, and `makeSorter` (pipeline/sort.ts) already applies it in array order with the per-machine manual order as final tiebreaker.

## Decisions (grounded; chassis per Nathan's sketch)

- **D-1 — The pane is the grouping chassis, and it owns the `sort` slot WHOLESALE:** `Sort By` (pane-flip disclosure, closes on pick — single-slot, exactly Group By) · `Order` (direction ValueRow) · `Sub-Sort` (picker row, the Sub-Group pattern) · its sub-tier `Order` · separator · the example order middle. Every pane write reconstructs the whole array from its two slots — `[primary]`, `[primary, sub]`, or `undefined` — the Group By wholesale-replacement precedent. A foreign 3+-key array (hand- or agent-authored sidecar) is honored by the pipeline and rendered by its first two slots until the first pane write, which replaces the slot whole; the pane never does splice-and-promote algebra.
- **D-2 — Sort By offering (the HONEST set — only what `makeSorter` actually ranks):** **None** (check when unsorted; picking it clears the whole sort — writes `sort: undefined` so the key drops from disk, and NO path ever writes `sort: []`) + **Title** and **Modified** (`RESERVED_PROPERTY_ID.title` / `.modifiedAt`, special-cased rows — neither is a schema def; `buildCriterion` handles both by reserved id) + every schema def whose `declaredType` ∈ `select · status · number · datetime · checkbox · url · multi_select`, minus the Sub-Sort's current property and minus reserved ids (no double-listing if the schema carries them). `context` and `file` are EXCLUDED even though `buildCriterion` routes them — `sortText` returns `''` for both (sort.ts), so they'd be no-op sorts; never offer what the extractor can't rank. Picking writes a fresh `{ property_id, direction: 'ascending' }` into slot 0 (the Group By reset-on-pick pattern). Trailing summary in the `groupByValue` treatment: the property's name, or `None`. The disclosure hides the rest of the pane while open and closes on pick — GroupingPane's exact `{!open && …}` guard — and the offering list itself gets the `middle` recipe's capped scroll (max-height + `overflow-eclipse-y`): the sortable offering can run a dozen properties, past the dropdown ceiling the four-row Group By list never tested.
- **D-3 — Order labels are per-type, the grouping vocabulary:** select/status → **Default / Reversed** (option order — grouping's locked labels for these types); datetime / Modified / number / checkbox → **Ascending / Descending**; text-ish (title, url, multi_select) → **A → Z / Z → A**. All map to on-disk `'ascending' | 'descending'`. Rendered only while a primary sort exists. Title's and Modified's glyphs come from an exported accessor in PropertyTypes.tsx (the title glyph currently lives in unexported `TITLE_META`; export it rather than duplicating the literal) — the special-cased rows never fall through `schema.find` into the D-6 dead-def branch.
- **D-4 — Sub-Sort mirrors Sub-Group:** rendered only while a primary sort exists; options = None + Title + Modified + sortable defs minus the primary's property; picking writes `[sort[0], { property_id, direction: 'ascending' }]`, None writes `[sort[0]]` (wholesale, per D-1 — no promotion of a foreign slot 2). Its sub-tier Order row (the `tier: 'sub'` treatment) is **scoped to Default / Reversed for now** regardless of type (Nathan's call — per-type sub labels can come later). When both Order rows are present they pair at the sub rhythm, exactly like grouping's Order + Sub-Order.
- **D-5 — Example order (the middle region):** rendered when the primary property carries a finite order — select/status — using grouping's PropertyPreview vocabulary verbatim: status renders its groups as muted headings with each group's chips beneath, select one flat chip run, both in the direction's EFFECTIVE order (Default = author's option order, Reversed = flipped). Non-finite primaries (datetime, number, text-ish, checkbox) collapse the middle + its separator — the `hasMiddle` logic. Chips are read-only (direction is the picker's job; sort has no custom order).
- **D-6 — A dead primary** (deleted def) still shows: the summary falls back to the raw id, Order defaults to Ascending/Descending labels, and None clears it — the pane never silently drops config it didn't write (the pipeline already skips unresolvable criteria).
- **D-9 — Sub-Sort disables row drag-reorder, by existing design:** TableView arms row reorder only under `sortKeys < 2` (`canReorderWithin`, TableView.tsx) — with two criteria the manual order is meaningless, so the grip hides. This is the accepted, documented consequence of authoring a sub-sort (Views.md states it; no new UI affordance) — not a regression to fix.
- **D-7 — Both doors route the leaf identically to Group:** SettingsPane `detailId === 'sort'` → `<SortingPane … label="Settings">`; ViewSettings `leaf === 'sort'` → `label="Views"`. `current="Sorting"` matches both doors' existing breadcrumb vocabulary.
- **Out of scope:** column-header click-to-sort (no such affordance exists; a future arc), authoring criteria past slot 1, the filter leaf, non-table renderers.

## Tasks

### Task 1: SortingPane core (TDD)

**Files:** Create `Pommora/src/renderer/src/Components/Detail/SortingPane.tsx` + `SortingPane.test.tsx`.

- [ ] Failing tests on the GroupingPane.test.tsx harness (createRoot/act, ResizeObserver stub, `window.nexus.views.save` spy — the view is arg index 2): unsorted shows Sort By + None and NO Order/Sub-Sort rows; the disclosure lists None + Title + Modified + sortable defs and EXCLUDES a context/file def; a pick writes `sort: [{property_id, direction:'ascending'}]`; per-type Order labels (status → Default/Reversed, datetime → Ascending/Descending); Sub-Sort pick writes slot 1 and its sub Order shows Default/Reversed; None on Sort By writes `sort: undefined` (never `[]`); a pane write over a foreign 3-key array replaces the slot wholesale (D-1 — the write is exactly the two-slot shape, no splice/promotion); a `_title` primary renders its name + glyph (not the dead-def fallback).
- [ ] Implement: sortable-type set + per-type direction options; ValueRow/summary shapes on the GroupingPane patterns (self-contained pane, sharing `groupingPane.css` classes, PickerControl, menu primitives).
- [ ] Gates green → commit `feat: SortingPane core — Sort By, Order, Sub-Sort on the grouping chassis`.

### Task 2: Example order middle

**Files:** Modify `SortingPane.tsx` + `SortingPane.test.tsx`.

- [ ] Failing tests: a status primary shows its group headings + chips; Reversed flips the run; a datetime primary collapses the middle.
- [ ] Implement the PropertyPreview-vocabulary middle (separator + `gp.middle` + `overflow-eclipse-y`), direction-aware.
- [ ] Gates green → commit `feat: the example-order preview under finite sorts`.

### Task 3: Effective-sort gating (D-9)

**Files:** Modify `Pommora/src/renderer/src/Detail/Views/pipeline/sort.ts` + `sort.test.ts`, `Detail/Views/Table/TableView.tsx`.

- [ ] Failing tests: `resolvedSortCount` counts only criteria `buildCriterion` resolves (dead property → 0; dead + live → 1; tier → 0).
- [ ] Export `resolvedSortCount(sort, schema)` from sort.ts; TableView's `sortKeys`, `sortedOrGrouped`'s sort half, and `structuralOrder` consume it (memoized alongside the existing view-derived memos — no per-row work).
- [ ] Gates green → commit `fix: gate row-drag + manual order on effective sorts, not raw criteria`.

### Task 4: Door routing + docs

**Files:** Modify `SettingsPane.tsx` (sort branch before `blankLeaf`), `ViewSettings.tsx` (sort branch before the blank fallback + the stale "Group/Filter/Sort ship blank" comments in both files), `.claude/Features/Views.md` (pane surface bullet beside Grouping's; Pending restated to Filter-only; the D-9 consequence stated — two sort criteria retire row drag-reorder by design), `.claude/History.md` (entry on merge).

- [ ] Route both doors, correct the comments, fold docs.
- [ ] Gates green → commit `feat: open the Sort leaf through both doors` (docs bundled).

**Close-out:** post-functional CDP UIX review against the live app (author a sort, flip direction, sub-sort, verify the table reorders), then merge `sort-pane` → main ff, History entry, simplifier pass.
