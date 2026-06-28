## Table Views — Part 1 (Plumbing) Implementation Plan — V2

> ### ✅ SHIPPED — POST-COMPACT PICKUP (read this first)
>
> **All 11 tasks below are DONE** — built TDD, each simplify- + code-reviewed before commit, on the **`views-plumbing`** worktree (commits `d5ed3ac`…`e89d94e`). **Full suite 713/713, both typechecks fully green. Do NOT rebuild any task.**
>
> **Where I am:** worktree `/Users/nathantaichman/The Studio/Projects/Pommora-views-worktree` (branch `views-plumbing`). Its `React/node_modules` is a **symlink** to the sibling `Pommora-react-worktree` (vitest works as-is — do NOT `npm install`). Run tests from the React dir: `cd "…/Pommora-views-worktree/React" && ./node_modules/.bin/vitest run [filter]` (the vitest `@shared` alias is now config-dir-relative, so `--root` works from anywhere too). Typecheck: `tsc --noEmit -p tsconfig.node.json` + `-p tsconfig.web.json`.
>
> **⛔ COMMIT RULE:** stage **explicit paths only — never `git add -A`**. The untracked `React/node_modules` symlink escapes the `node_modules/` gitignore and `-A` commits it (mode 120000). (Learned the hard way; see memory.)
>
> **⏸ BLOCKED — waiting on Nathan (his explicit instruction):** do NOT merge or touch `pommora-react`. A parallel React session is finishing its own work there (it committed Task 5 = `3bb170c`, which bundled my group files, + a *partial, non-canonical* Task 6). **Wait for Nathan to say that session is done, then COORDINATE the branch reconciliation WITH him** — `views-plumbing` is the keeper (a clean fast-forward descendant of `main`); do not auto-merge.
>
> **NEXT (after reconciliation):**
> - **Part 2 — table UIX.** Nathan designs the table in **Figma first**, then build the table + chips as direct `design-system/components/Chips/` components (on `tokens/chip.css.ts`, shared by select/multi/status — NOT Swift ports), routed to the `ResolvedColumn[]` / `ResolvedGroup[]` seams from `resolveView`. Part 2 also owns the **render concerns deferred from Part 1**: the group/sort **column hoist before `_title`**, **column widths**, **relation/tier chip resolution** (`Detail/Scope.ts` `findContext`), and replacing TableView's minimal render. Inline cell editor: glass-control chip pickers, plain inputs, a "Calendar" date placeholder, native menus for simple actions.
> - **Part 3 — View Settings** dropdown + Sort/Filter/Group/Layout panes + operator picker (narrower than the evaluator matrix) + view rename/dup/delete + `open_in`/`display_as`, wiring the already-shipped `views:save/reorder/delete` + `activeViews` IPC.
>
> **Deferred cleanups (Nathan's call, logged in Handoff):** (1) Biome config-vs-code quote mismatch (repo-wide); (2) a generic `.nexus` map-store factory (folds/tableHeadingColumns/activeViews triplication); (3) a `relPosix(root,abs)` helper (loadValues + watcher).
>
> **Full state → `React/.claude/Handoff.md`; locked decisions → `React/.claude/History.md`.** The task list below is the build record (kept for reference; the `- [ ]` boxes were not ticked during inline execution — the banner is the source of truth on status).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the UI-agnostic foundation for Collection Table Views — the on-disk `SavedView` contract, per-machine active-view pointer, file-sourced value loading, and a pure pipeline (column resolution → filter → group → sort) — so Part 2's Figma-designed table routes to stable seams.

**Architecture:** Ports the Swift build's view pipeline behavior (NOT its AppKit rendering), with two deliberate, documented divergences. Pure functions in `renderer/.../Views/pipeline/` (no fs/React) consume a `SavedView` + `PropertyDefinition[]` + `ViewRow[]` and emit `ResolvedColumn[]` + `ResolvedGroup[]`. Main IPC owns persistence + batch value loading. On-disk shapes match Swift key-for-key.

**Tech Stack:** TypeScript, zod, Electron IPC (`{ ok }` envelope), Vitest. Reused seams (all verified present): `shared/propertyValue.ts` (`parsePropertyValue`/`PropertyValue`), `io/atomicWrite.ts` (`readJsonObject`/`writeJson`), `sidecarIO.ts` (`readSidecar`/`writeSidecar`), `paths.ts`, `main/ids.ts` (`newId()`), `Detail/Scope.ts` (`findContext`), `readNexus.ts` (`splitFrontmatter`).

### Global Constraints

- **On-disk parity with Swift** for `SavedView` keys AND filter `op` raw strings (snake_case — see Task 6). Sidecar `views[]` stays a zod `looseObject` so foreign keys survive a rewrite.
- **Files canonical, no SQLite read path:** values from `.md` frontmatter; relations from the loaded `NexusTree`.
- **Main owns fs;** narrow typed preload bridge; IPC never throws (`{ ok: true,… } | { ok:false, error }`).
- **`shared/` is renderer-safe** (no `node:*`, no fs, no React) — it must not import from `main/`.
- **Grouping:** only `select | status | checkbox | date/datetime`. NOT number/multi-select/url/relation/file/last-edited.
- **`_modified_at` is NOT a default-on column** (deliberate divergence from Swift).
- **DELIBERATE DIVERGENCES (document in code, not "ports"):**
  1. **Multi-key sort** — Swift's pipeline is single-criterion; Part 1 honors the full `sort[]` (priority = array order) per Nathan's request. A superset, not parity.
  2. **Branch by declared type** for empty/ambiguous handling — Swift trusts the codec's shape-inferred value; Part 1 branches the comparator/bucket by the column's *declared* type but still reads the codec value (a shape-mismatched value sorts/buckets as "unknown," same end result as Swift).
- **Render-only concerns deferred to Part 2:** the group/sort column **hoist** before `_title`, column **widths**, and **relation/tier chip resolution** (`Scope.findContext`). Part 1 emits column order verbatim + the group/sort property id; Part 2 hoists.
- **TDD, one green commit per task.** A **synthetic** fixture `__fixtures__/collection-with-status.json` (status property: 3 groups, options incl. a minted `opt_*` value; a datetime property; a Table view with `order_mode:"manual"` status grouping + a descending status sort) is the conformance fixture — NOT real vault data.
- **Biome auto-formats on write** — don't hand-align; on a whitespace Edit failure, re-read and retry.
- **Out of scope (Parts 2/3):** table/cell components, inline editor, settings dropdown + the operator *picker*, `display_as` variants, view rename/dup/delete UI, `open_in`, the hoist/width/resolution render concerns above, multi-select grouping, manual sort order.
- **Part-2 directive (binding, recorded here):** chips are **direct components in `design-system/components/Chips/`**, built on React's existing chip styles (`tokens/chip.css.ts`) — shared by select/multi/status — NOT inline `<span>`s, NOT Swift ports.

---

### File Structure

```
src/shared/
  views.ts / views.test.ts        NEW — SavedView types + zod (lenient group decode w/ defaults) + mintDefaultView (sentinel id)
  schemas.ts                      MODIFY — views: z.array(savedView) (kept loose)
  types.ts                        MODIFY — extend ViewRow; add ResolvedColumn {id,kind} / ResolvedGroup / kinds
src/renderer/src/Detail/Views/    (TableView + ContainerView importer move here from Detail/Table/)
  pipeline/
    value.ts / value.test.ts          NEW — resolveFieldValue + declaredType (branch key)
    sort.ts / sort.test.ts            NEW — makeSorter (multi-key, type-complete like Swift)
    group.ts / group.test.ts          NEW — structural + property + flat + flatten
    filter.ts / filter.test.ts        NEW — applyFilter (evaluator matrix) + RAW op constants
    columns.ts / columns.test.ts      NEW — resolveColumns → ResolvedColumn[] (verbatim, no hoist/width)
    resolveView.ts / .test.ts         NEW — orchestrator seam
  Table/ (Part 2)  Gallery/ (later)  columns/ settings/ (later — empty)
src/main/
  io/activeViews.ts / .test.ts        NEW — per-machine pointer (folds.ts pattern)
  crud/views.ts / .test.ts            NEW — save/reorder/delete (sentinel→newId on save)
  crud/loadValues.ts / .test.ts       NEW — batch frontmatter read
  paths.ts / index.ts                 MODIFY — activeViews path; register IPC
src/preload/index.ts                  MODIFY — expose IPC
__fixtures__/collection-with-status.json  NEW — synthetic conformance fixture
```

Old `Detail/Table/pipeline.ts` + `pipeline.test.ts` are deleted in Task 11.

---

### Task 1: SavedView contract + synthetic fixture (`shared/views.ts`)

**Files:** Create `src/shared/views.ts`, `views.test.ts`, `__fixtures__/collection-with-status.json`; Modify `schemas.ts`.

**Interfaces — Produces:** `ViewType`; `SortCriterion {property_id; direction:'ascending'|'descending'}`; `FilterRule {property_id; op:string; value?:string}`; `FilterGroup {match:'all'|'any'; rules:(FilterRule|FilterGroup)[]}` (**recursive** — a child is a rule OR a nested group → mixed AND/OR like `(A AND B) OR C`; a flat filter whose `rules` hold only `FilterRule`s is byte-identical to Swift's, so simple filters round-trip both builds, nested ones are React-ahead until Swift aligns); `GroupConfig = {kind:'structural'} | {kind:'flat'} | {kind:'property'; property_id; order_mode:'configured'|'reversed'|'manual'; order?:string[]; date_granularity?:'day'|'week'|'month'|'year'; empty_placement:'top'|'bottom'; hide_empty_groups:boolean}`; `SavedView {…all keys…; sort?:SortCriterion[]; filter?:FilterGroup; group?:GroupConfig}`; `const savedView` (loose); `const DEFAULT_VIEW_ID = 'view_default'`; `mintDefaultView(schema): SavedView`.

- [ ] **Step 1: Author the synthetic fixture** `__fixtures__/collection-with-status.json` — a `_pagecollection.json` shape with: `properties` = [a `status` prop `prop_status` with 3 groups (upcoming: `not_started`,`opt_open`; in_progress: `in_progress`; done: `done`), a `datetime` prop `prop_when`]; `views` = [a Table view `view_1` (`name:"Table"`) with `property_order:["prop_status","_title","_tier3","_tier2","_tier1"]`, `hidden_properties:["_modified_at"]`, `group:{kind:"property",property_id:"prop_status",order_mode:"manual",order:["in_progress","opt_open","not_started","done"],empty_placement:"bottom",hide_empty_groups:false}`, `sort:[{property_id:"prop_status",direction:"descending"}]`].

- [ ] **Step 2: Failing tests** (`views.test.ts`): parse the fixture's `views[0]` → `type:'table'`, `property_order[0] === 'prop_status'`, group is property+manual with that `order`, `sort` array; **unknown `group.kind` → `{kind:'structural'}`**; **legacy bare `{property_id:'p'}` → property WITH injected defaults** `order_mode:'configured'`, `empty_placement:'bottom'`, `hide_empty_groups:false` (assert all three present, not just `kind`); foreign key on the view object preserved.

- [ ] **Step 3:** Run → FAIL.

- [ ] **Step 4:** Implement. `savedView` = `looseObject`; `group` via a custom decoder mirroring [SavedView.swift:378-413](../../../Pommora/Pommora/Domain/Collections/SavedView.swift): map `kind`; legacy `{property_id}` (no kind) → property; **inject `order_mode/empty_placement/hide_empty_groups` defaults** via `decodeProperty`; unknown → structural. `sort` optional array.

- [ ] **Step 5:** Wire `schemas.ts` (`views: z.array(savedView).optional()` in both collection + set sidecars). **Also thread views into the tree** (without this the config never reaches the renderer): add `views?: SavedView[]` to `CollectionNode` AND `SetNode` (`shared/types.ts`), and read `meta.views` (via `savedView`, lenient) in `readNexus.ts` `readSet` + `readPageCollection`. Run `npx vitest run src/shared && npm run typecheck`.

- [ ] **Step 6: Commit.** `git add src/shared/views.ts src/shared/views.test.ts src/shared/schemas.ts "__fixtures__/collection-with-status.json" && git commit -m "feat(react): SavedView on-disk contract + lenient decode + synthetic fixture"`

---

### Task 2: ViewRow + resolved seam types (`shared/types.ts`)

**Interfaces — Produces:** `ViewRow {id; title; icon?; path; parentSetId?; frontmatter: PageFrontmatter}` (was `frontmatter?: Record<string,unknown>`); `type ColumnKind='title'|'property'|'tier'|'modified'`; `ResolvedColumn {id:string; kind:ColumnKind}` (**no width** — Part 2 owns it); `type GroupKind='structural-set'|'property'|'ungrouped'` (no `structural-collection` — React renders one container, so the top structural groups are always its child Sets, never Collections); `ResolvedGroup {key:string; kind:GroupKind; items:ViewRow[]; children?:ResolvedGroup[]; isCollapsed:boolean}`.

- [ ] **Step 1:** Remove the old `ViewField`/`SortSpec`/`FilterRule`/`ViewSpec`/old `ResolvedGroup` from `types.ts`. Add the above (import `PageFrontmatter` from `./schemas`). `frontmatter` is **required** — Task 5's `flattenContainer` supplies a minimal `{ id }` when values aren't loaded.
- [ ] **Step 2:** `npm run typecheck` will flag the old pipeline + TableView (gone/rewired in Task 11) — expected, not yet green.
- [ ] **Step 3: Commit.** `git add src/shared/types.ts && git commit -m "feat(react): ViewRow + ResolvedColumn/ResolvedGroup seam types"`

---

### Task 3: Field-value extraction (`pipeline/value.ts`)

**Consumes:** `ViewRow`, `PropertyDefinition`/`PropertyType`/`RESERVED_PROPERTY_ID`, `parsePropertyValue`.
**Produces:** `declaredType(propertyId, schema): PropertyType | 'title' | 'tier'` — `_title`→`'title'`; **`_modified_at`→`'last_edited_time'`** (so filter routes it through the date matrix + sort treats it as the Recent preset — Swift filters `_modified_at` as a date, `FilterEvaluator.swift:64`); `_tier1/2/3`→`'tier'`; `_status` is a normal reserved id with NO special branch; else `schema.find(id)?.type`. **Branch on the snake_case `PropertyType` values** (`multi_select`, `last_edited_time`, …) — the camelCase `multiSelect`/`lastEditedTime` used as shorthand elsewhere in this plan are `PropertyValue.kind` tags (a different axis); the real `switch` cases are snake_case; `resolveFieldValue(row, propertyId, schema): PropertyValue` — `_title`→`{kind:'select',value:title}`; `_modified_at`→`{kind:'datetime',value: frontmatter.modified_at}`; `_tier1/2/3`→`{kind:'relation',value: frontmatter.tierN ?? []}`; `prop_*`→`parsePropertyValue(frontmatter.properties?.[id])`. **No re-coercion** — the codec's `kind` is trusted; callers branch on `declaredType` and read this value; a shape mismatch yields an unmatched value (treated as unknown by sort/group, matching Swift).

- [ ] **Step 1: Failing tests** — each reserved id + a status/select/date/number user prop from a synthetic row; absent prop → `{kind:'null'}`; `_status` is not specially branched.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(react): schema-typed field-value extraction"`

---

### Task 4: Sort (`pipeline/sort.ts`)

**Port of** [SortComparator.swift](../../../Pommora/Pommora/Features/Detail/ViewPipeline/SortComparator.swift), **extended to multi-key** (divergence #1).
**Produces:** `makeSorter(sort: SortCriterion[] | undefined, schema): ((rows:ViewRow[])=>ViewRow[]) | null` — `null` when no usable criterion.

- [ ] **Step 1: Failing tests** (against a synthetic schema): select/status sort by **schema option order** (unknown→last); number numeric (absent→first asc); checkbox false<true; date chronological (absent→earliest); **lastEditedTime sorts by date** (Swift `dateOf`); **relation/file extract to "" → effective no-op tie** (Swift `sortText` default); presets `_title` (case-insensitive), `_id` (ULID), `_modified_at` (modified, created fallback); **multi-key**: primary then secondary; stable ties; descending flips.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement decorate-sort. `propertySorter` is **type-complete** (every `PropertyType` has a branch, mirroring Swift `:50-63` — select/status→optionOrderIndex, number→numeric, date/datetime/**lastEditedTime**→date, checkbox→bool, url/multiSelect/relation/file→`sortText` [url→address, select/status→value, multiSelect→joined, **relation/file→""**]). `optionOrderIndex`: select options enumerated; status options flattened across the 3 groups (select XOR status per def — never merge both). Unknown value → `Number.MAX_SAFE_INTEGER`. Multi-key: compare criteria in array order; a criterion whose property isn't in the schema is skipped; `null` only if no criterion resolves. (Note: `isSortable` filtering is a Part-3 *picker* concern, NOT here — the comparator handles all types like Swift.)
- [ ] **Step 4:** PASS. **Step 5: Commit.** `git commit -m "feat(react): type-complete multi-key view sort (extends SortComparator)"`

---

### Task 5: Grouping + flatten (`pipeline/group.ts`)

**Port of** [GroupResolver.swift](../../../Pommora/Pommora/Features/Detail/ViewPipeline/GroupResolver.swift) (container-scope structural + property + flat) + [DateBucket.swift](../../../Pommora/Pommora/Features/Detail/ViewPipeline/DateBucket.swift). Swift's vault-scope `structuralPageCollection` is dropped (React renders one container). **Handles BOTH a Collection view and a Set view identically** — `CollectionNode` and `SetNode` share the `{sets, pages}` shape, so the container's direct child Sets become the top disclosure groups either way. React does NOT need Swift's `isStructuralAnchor` mechanism: `setTree` is built from `node.sets` (the real folder tree from `readNexus`, which walks directories), so **empty Sets — folders with no direct pages — still appear as disclosure groups**.

**Produces:** `flattenContainer(node: CollectionNode|SetNode, valuesByPageId: Record<string,PageFrontmatter>): {rows: ViewRow[]; setTree}` — builds `setTree` by recursively walking `node.sets` (captures every Set, incl. empty ones), and walks pages stamping `parentSetId` + attaching `valuesByPageId[page.id] ?? { id: page.id }` (minimal fallback); `dateBucketKey(iso, granularity)`; `bucketKey(row, propertyId, schema, granularity): string | null`; `resolveGroups(rows, group, schema, setTree, sorter): ResolvedGroup[]`.

- [ ] **Step 1: Failing tests**: structural (collection container) — two top-level Sets + a nested Sub-Set + a root page → nested `children`, root page in trailing `ungrouped` band; **structural (set container)** — a `SetNode` with two Sub-Sets + own pages → Sub-Sets as top disclosure groups, own pages in the band (proves both scopes share one path); **empty Set** — a Set folder with no direct pages still appears as a (childless or child-bearing) disclosure group; zero Sets → single headerless band. property — manual order `['in_progress','opt_open','not_started','done']` → buckets in that order, empty buckets dropped, no-value rows → bucket keyed **`'_ungrouped'`** titled "No <name>" placed per `empty_placement`, dropped by `hide_empty_groups`; checkbox nil → `'false'` bucket (no no-value bucket); date granularity month buckets same-month dates together; configured/reversed vs schema order; non-groupable group property (number) → **structural fallback**. flat → one band.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** Implement. `bucketKey` branches on `declaredType` (select/status→value, checkbox→`'true'|'false'`, date→`dateBucketKey`, else `null`). `bucketOrder` (manual: `order`+sorted tail; configured: schema option order then tail; reversed: configured reversed). No-value bucket key = `'_ungrouped'` (match Swift, so `collapsed_groups` round-trips). Structural builder recurses `setTree`; `resolveGroups` dispatches with the groupable-type guard (non-groupable → structural). `dateBucketKey`: day `YYYY-MM-DD`, week ISO `YYYY-Www`, month `YYYY-MM`, year `YYYY`.
- [ ] **Step 4:** PASS. **Step 5: Commit.** `git commit -m "feat(react): structural + property grouping with manual status order + flatten"`

---

### Task 6: Filtering (`pipeline/filter.ts`)

**Ports** Swift's flat per-rule evaluator + per-type matrix in `FilterEvaluator.swift` (NOT the narrower picker); the **recursion (nested groups) is net-new React** — Swift's `rules` are flat `[FilterRule]`. Operator raw strings are **snake_case** (on-disk parity).

**Produces:** `const FILTER_OPS = {is:'is', isNot:'is_not', contains:'contains', doesNotContain:'does_not_contain', isEmpty:'is_empty', isNotEmpty:'is_not_empty', greaterThan:'greater_than', lessThan:'less_than', onOrAfter:'on_or_after', onOrBefore:'on_or_before'}`; `applyFilter(rows, filter: FilterGroup | undefined, schema): ViewRow[]`.

Evaluator matrix to honor (by declared type):
- **number:** greater_than, less_than, is, is_not, is_empty, is_not_empty
- **date / datetime / last_edited_time** (incl. the `_modified_at` reserved column, via `declaredType`→`last_edited_time`): on_or_after, on_or_before, is_empty, is_not_empty
- **select / status / url (text):** is, is_not, contains, does_not_contain, is_empty, is_not_empty
- **multi_select:** is, is_not, contains, does_not_contain, is_empty, is_not_empty (membership)
- **checkbox:** is, is_empty, is_not_empty
- **tier relations `_tier1/2/3`:** is, is_not, contains, does_not_contain, is_empty, is_not_empty (membership over the id list)
- **user relation / file:** is_empty, is_not_empty only (is/is_not are **no-op passes**)

`match:'all'`=AND, `'any'`=OR; unknown op = no-op pass; empty `rules` ⇒ all rows. **Recursive:** a `rules` child that is itself a `FilterGroup` (has `match`+`rules`) recurses (`all`→every / `any`→some); a child with `property_id`+`op` evaluates as a rule — that shape check is how rule vs nested group is told apart.

- [ ] **Step 1: Failing tests** — AND vs OR; **nested `(A AND B) OR C` evaluates correctly** (mixed AND/OR via a sub-group); a representative op per type group; tier membership `contains` vs user-relation `is` no-op; unknown op passes; empty rules passthrough; **raw `op` strings are snake_case**.
- [ ] **Step 2:** FAIL. **Step 3:** Implement (extract via Task 3, branch on `declaredType`, evaluate per matrix). **Step 4:** PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(react): type-aware view filter (FilterEvaluator port, snake_case ops)"`

---

### Task 7: Column resolver (`pipeline/columns.ts`)

**Port of** [TableColumnResolver.swift](../../../Pommora/Pommora/Features/Detail/Table/TableColumnResolver.swift) + [VisiblePropertyOrder.swift](../../../Pommora/Pommora/Features/Detail/ViewPipeline/VisiblePropertyOrder.swift). **No hoist, no width** (Part 2).

**Produces:** `resolveColumns(view: SavedView, schema): ResolvedColumn[]`.

- [ ] **Step 1: Failing tests** (fixture view): `property_order` verbatim (prop_status first, title second); `hidden_properties` excluded except `_title`; tiers `_tier3,_tier2,_tier1` default-on unless hidden/placed; **`_modified_at` NOT default-on**; schema prop absent from order appends; `_title` always present (front-inserted if missing); each column emits `{id, kind}` (kind via reserved-id map).
- [ ] **Step 2:** FAIL. **Step 3:** Implement two-pass (verbatim → append unaccounted) + Pass-3 default-on tiers (no `_modified_at`) + title guarantee. No hoist/width. **Step 4:** PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(react): table column resolver (verbatim port, render concerns deferred)"`

---

### Task 8: resolveView orchestrator + default-view mint (`pipeline/resolveView.ts` + `shared/views.ts`)

**Produces:** `resolveView({rows, setTree, view, schema}): {columns: ResolvedColumn[]; groups: ResolvedGroup[]}` — columns (Task 7) + filter (6) → group (5) → sort-within-group (4). **View-source-agnostic:** `view`/`rows`/`schema` are all passed explicitly, so a future context-dashboard embed reuses this verbatim with its own stored `SavedView` + a target ref — do NOT couple the view to the container or read `views[]` inside the pipeline. `mintDefaultView(schema): SavedView` — `id: DEFAULT_VIEW_ID` (sentinel), `type:'table'`, `property_order:['_title', ...userPropIds]`, `group:{kind:'structural'}`, no `sort`, NO `_modified_at`.

- [ ] **Step 1: Failing tests** — full pipeline over the fixture + seeded rows reproduces: groups in manual order with empty `done` dropped + a "No <status>" band; columns prop_status-first; sort within groups. `mintDefaultView` shape (title-first sentinel-id, structural, no modified, no sort).
- [ ] **Step 2:** FAIL. **Step 3:** Implement orchestrator + `mintDefaultView` (pure, sentinel id — no `ids.ts` import). **Step 4:** PASS. `npm run typecheck`.
- [ ] **Step 5: Commit.** `git commit -m "feat(react): resolveView orchestrator + default-view minting"`

---

### Task 9: Per-machine active-view pointer (`io/activeViews.ts` + IPC)

**Pattern:** mirror [folds.ts](../src/main/io/folds.ts).
**Produces:** `type ActiveViews = Record<string,string>`; `readActiveViews(root)` (lenient→`{}`); `writeActiveViews(root, containerId, viewId)` (empty viewId clears); IPC `activeViews:get`/`activeViews:set`; preload `window.nexus.activeViews.{get,set}`.

- [ ] **Step 1:** Add `activeViews: 'activeViews.json'` to `NEXUS_CONFIG_FILES` (`paths.ts`).
- [ ] **Step 2: Failing test** — write→read round-trip; absent→`{}`; empty viewId deletes key.
- [ ] **Step 3:** FAIL. **Step 4:** Implement (copy folds.ts shape). **Step 5:** PASS.
- [ ] **Step 6:** Register IPC (`index.ts`) + preload. `npm run typecheck`.
- [ ] **Step 7: Commit.** `git commit -m "feat(react): per-machine active-view pointer + IPC"`

---

### Task 10: View persistence IPC (`crud/views.ts`)

**Pattern:** read-modify-write the sidecar via `readSidecar`/`writeSidecar`, preserving foreign keys.
**Produces:** `saveView(containerPath, kind: 'collection'|'set', view)` — `kind` selects the sidecar (`_pagecollection.json` vs `_pageset.json`, via `SIDECAR_FILENAME`/`readSidecar`); upsert by `id`; **if `view.id === DEFAULT_VIEW_ID`, assign `newId()`-based `view_<ulid>` before writing**; `reorderViews(containerPath, kind, orderedIds)`; `deleteView(containerPath, kind, viewId)` (refuse last); IPC `views:save|reorder|delete` (carry `kind`); preload `window.nexus.views.{save,reorder,delete}`. The renderer passes the selection's kind (`'collection'|'set'`).

- [ ] **Step 1: Failing test** — save into a sidecar fixture round-trips; sentinel id → real `view_<ulid>` on save; a foreign top-level key + a foreign key inside an existing view survive; delete-last refused.
- [ ] **Step 2:** FAIL. **Step 3:** Implement (`newId()` from `main/ids.ts` here in main — allowed). **Step 4:** PASS.
- [ ] **Step 5:** Register IPC + preload. `npm run typecheck`.
- [ ] **Step 6: Commit.** `git commit -m "feat(react): view persistence IPC (sentinel→ulid, foreign keys preserved)"`

---

### Task 11: Batch value loading + rewire TableView (`crud/loadValues.ts` + `Detail/Views/`)

**Consumes:** `readPage`/`splitFrontmatter`, `pageFrontmatter`, `flattenContainer`, `resolveView`, `mintDefaultView`. **Depends on Tasks 5, 8** (not just 2) — run after them.

**Produces:** `loadValues(rootPath, containerRelPath): Promise<Record<string,PageFrontmatter>>`; IPC `view:loadValues`; preload `window.nexus.loadValues`.

- [ ] **Step 1:** Delete old `Detail/Table/pipeline.ts` + `pipeline.test.ts`. **Move** `TableView.tsx` → `Detail/Views/Table/TableView.tsx` and update its importer in `Detail/ContainerView.tsx`.
- [ ] **Step 2: Failing test** (`loadValues.test.ts`) — temp nexus with a collection + nested set + pages carrying `properties`/`tier1` → correct `pageId → PageFrontmatter` map.
- [ ] **Step 3:** FAIL. **Step 4:** Implement `loadValues` (recursive walk + `readPage`/`splitFrontmatter` + `pageFrontmatter` parse). PASS.
- [ ] **Step 5:** Register IPC + preload. Add `resolveContainerSchema(tree, source): PropertyDefinition[]` — a Collection uses its own `properties`; a Set (any depth) inherits its **ancestor Collection's** `properties` (schema is Collection-only) by finding the top-level Collection that owns the Set's path. Rewire `TableView`: resolve schema via that helper; pick the active view (the `activeViews` pointer from Task 9 → that view; else `source.views?.[0]`; else `mintDefaultView(schema)`) → `await window.nexus.loadValues(path)` on container open → `flattenContainer(source, values)` → `resolveView({rows, setTree, view, schema})` → render groups→rows (minimal render; real columns/cells are Part 2). `npm run typecheck` + `npx vitest run` (full suite green).
- [ ] **Step 6: Commit.** `git commit -m "feat(react): batch value loading + rewire TableView onto resolveView seam"`

---

### Self-Review

**Spec coverage:** contract→T1; ViewRow/seam→T2; values→T3/T11; sort→T4; grouping→T5; filter→T6; columns→T7; orchestrator+mint→T8; active-view→T9; persistence→T10; value-load+rewire→T11. Relation/tier resolution, width, hoist → explicitly Part 2 (reuse `Scope.findContext`). All Part-1 spec items covered.

**Placeholder scan:** none. Open decisions are surfaced (multi-key divergence, declared-type divergence — both in Global Constraints with rationale).

**Type consistency:** `SavedView`/`GroupConfig`/`SortCriterion`/`FilterGroup`/`DEFAULT_VIEW_ID` (T1) → consumed T4-T11. `ViewRow`/`ResolvedColumn{id,kind}`/`ResolvedGroup` (T2) → onward. `declaredType`/`resolveFieldValue` (T3) → T4/T5/T6. `flattenContainer`/`resolveGroups` (T5), `resolveColumns` (T7) → composed by `resolveView` (T8). `mintDefaultView` sentinel id (T8) → swapped in T10. No `ids.ts` import in `shared/`.

**Build order:** T1-T8 are pure/independent (T2 leaves old pipeline broken until T11 deletes it — safe, not on a shipping path). T9/T10 are main-side. **T11 depends on T5+T8+T10** — linear order satisfies it; if parallelized, gate T11 on those three.

#### Confirmed against Swift (V2 review fixes folded)
- Filter `op` raw strings snake_case + evaluator matrix (incl. tier-membership vs user-relation-presence) — `FilterEvaluator.swift`.
- Sort comparator type-complete (relation/file→"", lastEdited→date); `isSortable` is Part-3 picker only.
- `mintDefaultView` shared-safe via sentinel id; real ulid assigned in main on save.
- No-value bucket key `'_ungrouped'` (collapse round-trip).
- Lenient group decode injects `order_mode`/`empty_placement`/`hide_empty_groups` defaults.
- Synthetic fixture (no live-vault dependency).

#### Carried open decisions (for Nathan)
1. Multi-key sort is a deliberate superset of Swift's single-key pipeline — keep, or match Swift single-key?
2. Branch-by-declared-type vs Swift's pure shape-inference — keep the correctness lean, or mirror Swift exactly?
