### Table Views — Part 1: Plumbing Spec

The UI-agnostic foundation for real Collection **Views** (Table first) in the React build: the on-disk view contract, value loading, and the type-aware sort/group/column engine. Built so Part 2 (the Figma-designed table UIX) and Part 3 (the settings dropdown) plug into stable seams without reworking foundations.

Product truth: root `PommoraPRD.md` + `// Features // Views.md`, `Properties.md`, `PageCollections.md`. Swift is the reference implementation; this ports its **data model + behavior**, not its AppKit rendering.

#### The three parts (why plumbing is standalone)

1. **Plumbing (this spec)** — data contract, persistence, value loading, the pure pipeline (column resolution → filter → group → sort). No real UI. Provable by unit tests + a seeded render.
2. **Table UIX** — designed in Figma, then built and *routed* to the seams below (resolved columns, resolved groups, per-cell value+display data). Includes the real chip components and the inline cell editor.
3. **Settings dropdown** — the toolbar popover (root menu → Layout / Sort / Filter / Group / Edit Properties) that mutates the view config through the Part 1 persistence layer.

Keeping Part 1 free of components is the point: the plumbing review and the table UIX can proceed without colliding.

#### Core principle: align on the on-disk contract, diverge freely on rendering

The sidecar shapes below match Swift **key-for-key** so a view authored by either build round-trips through the other. Everything above the file — pipeline internals, component structure, React's runtime view-spec — is React's own. (Per `[[align-at-the-boundary-not-flatten-react]]`.)

---

### 1 — The view contract (on disk)

A `SavedView` lives in the existing `views: []` slot of `_pagecollection.json` and depth-1 `_pageset.json` (deeper Sub-Sets carry none). The slot is already a zod `looseObject` passthrough today; this replaces it with a real schema while **keeping `looseObject` so foreign keys survive a rewrite** (React's foreign-key-preservation guarantee).

```
SavedView {
  id: "view_<ulid>"
  name: string
  icon?: string
  type: "table" | "gallery" | "board" | "list" | "cards"   // table renders now; rest decode + park
  property_order: string[]          // property IDs; _title is NOT required to be first
  hidden_properties: string[]
  column_widths?: { [propertyId]: number }
  collapsed_groups?: string[]
  card_size?: "small" | "medium" | "large"
  show_cover?: boolean
  show_banner?: boolean
  sort?: { property_id, direction: "ascending" | "descending" }[]   // array = multi-key, priority = order
  filter?: { match: "all" | "any", rules: ( {property_id, op, value?} | FilterGroup )[] }  // recursive: nested groups → mixed AND/OR
  group?: GroupConfig
}

GroupConfig =
  | { kind: "structural" }                       // default — group by Set (recursive)
  | { kind: "flat" }
  | { kind: "property", property_id,
      order_mode: "configured" | "reversed" | "manual",
      order?: string[],                          // option values, for manual
      date_granularity?: "day"|"week"|"month"|"year",
      empty_placement: "top" | "bottom",
      hide_empty_groups: boolean }
```

**Decode is lenient** (mirrors Swift): unknown `group.kind` → structural; a bare legacy `{property_id}` → property; missing fields take sane defaults — a malformed view never poisons the sidecar.

Reference shape: the real `The Nexus/Ideas/_pagecollection.json` (status property, two views, a `manual`-order status grouping) — modeled by a committed **synthetic** fixture `__fixtures__/collection-with-status.json` (the live vault isn't in-repo). The synthetic file is the conformance fixture.

**Reserved IDs** used inside `property_order` / `column_widths` / `hidden_properties`: `_title`, `_tier1`/`_tier2`/`_tier3`, `_modified_at`. Tier *values* live at the frontmatter root (`tier1/2/3` bare arrays); `_modified_at` derives from the file. User properties are `prop_<ulid>`.

#### Active-view pointer — per-machine, NOT in the sidecar

Which view is currently selected for a container is **session state, not data**: `{ containerId: viewId }` in a dedicated `.nexus/activeViews.json`, sync-excluded, read/written through helpers mirroring `io/folds.ts`. Switching views must not rewrite the sidecar (no `modified_at` churn, no cross-machine conflict). This is a deliberate, documented divergence from Swift's `state.json` location; the behavior (per-machine active view) is the same.

#### Forward-compat — embedded / linked views (guardrail, NOT scoped here)

Context dashboards will later embed **custom views of a collection** — like a Notion linked/inline database, where the embed carries its OWN view config (filter, sort, grouping, visible columns) distinct from the collection's own views. That embed config lives **with the embed** (the context dashboard's block storage) and targets a collection explicitly — a **separate affordance** from the collection sidecar's `views[]`, which are the container's *direct-viewing* views.

Part 1 must not block this, and doesn't: the pipeline is **view-source-agnostic**. `resolveView({view, rows, schema})` is pure over an explicit view + data; `loadValues(targetPath)` and `resolveContainerSchema(target)` key off the *target* collection, not where the view is stored. A future embed reuses the exact pipeline by supplying its own stored `SavedView` + a **stable target-Collection ID** (rename-safe — mirrors Notion's `data_source_id` reference and our existing by-ID links) — no rework. **Guardrail:** never couple a view's *source* to the container it renders; never assume sidecar `views[]` is the only view mechanism; keep `SavedView` self-contained (no implicit "I am the collection's own view"); filters/sorts already reference properties by ID, which an embed needs too.

*Validated against Notion's linked-database model (researched): the embed owns its view config and references the source by stable ID; the source owns schema + data + its own canonical views; multiple embeds of one Collection hold independent configs. Maps 1:1 onto Collection-sidecar `views[]` (source's own) vs a future embed's `{ target_collection_id, SavedView }` (owned by the embedder). The embed feature itself stays out of scope.*

---

### 2 — Property values

Per-page values are read from frontmatter: user properties under `properties: { prop_<ulid>: <encoded> }` (ID-keyed), tier relations as bare root arrays `tier1/2/3`, last-edited derived from `modified_at` (mtime fallback). The `PropertyValue` codec (`shared/propertyValue.ts`) already encodes/decodes at full parity with Swift (`{$status}`, `[{$rel}]`, `yyyy-MM-dd`, ISO datetime, bare arrays) and is reused unchanged.

**The pipeline branches by DECLARED schema type** (which comparator/bucket rule + how empties route) while reading the codec's value. Swift branches on the stored value's case plus the schema def; React branches on `PropertyDefinition.type` and reads the codec value — a value whose JSON shape doesn't match the declared type resolves to "unknown" (sorts/buckets like an empty), the **same end result as Swift** (a select stored as `"2026-01-01"` misses the select branch either way). React does NOT re-coerce values; this is an implementation note, not a behavior divergence.

A Set view inherits its **ancestor Collection's** property schema (schema is Collection-only; Sets carry views but not properties) — resolved by walking from the Set's path up to its owning Collection.

#### Value loading — lazy, file-sourced

Values load the way Swift sources them: from the canonical files, not SQLite. A main-process IPC (`view:loadValues(containerPath) → { [pageId]: properties }`) batch-reads frontmatter for the container's pages (own + every nested Set, any depth), invoked **when a container opens** — not eagerly in the initial nexus walk (keeps the walk light). The renderer's `ViewRow` carries the loaded `properties` map; the pipeline addresses values by property ID.

**Relation / tier chip resolution** (ULID → icon + title) resolves from the already-loaded `NexusTree` (contexts live there) — no SQLite read path. An unresolved id renders as a missing-target marker, not an error.

---

### 3 — Column resolution

Ported from Swift's `TableColumnResolver` + `VisiblePropertyOrder`: resolve a `SavedView` + schema into the ordered visible column list.

- `property_order` consumed **verbatim** (title may sit anywhere); `hidden_properties` excludes a column **except `_title`** (never hidden) and the cover (never a column).
- Schema properties absent from `property_order` and not hidden **append** at the end (a new property shows immediately).
- Tier columns (`_tier3`, `_tier2`, `_tier1`, in that order) are **default-on** — appended unless hidden or already placed. **`_modified_at` is NOT default-on** in React (deliberate divergence — Nathan's call); it appears only if explicitly in `property_order`.
- `_title` is always present: if absent from the order, inserted at the front.

**Group/sort hoist is a Part-2 render concern, not Part 1.** When a view is grouped-by or sorted-by a property, the table renders that column immediately **before `_title`** — applied at **render time by the table component** (Part 1's `resolveColumns` stays a verbatim port; stored `property_order` untouched, so the sidecar stays identical to Swift). Part 1 exposes the resolved columns + the view's group/sort property id; Part 2 hoists. (Swift doesn't auto-hoist — it's net-new React behavior.)

---

### 4 — The pipeline (filter → group → sort)

A pure rewrite of React's current string-blind pipeline into a schema-type-aware port of Swift's `GroupResolver` + `SortComparator`. Pure functions, no fs/React, unit-tested against the Swift behavior.

#### Grouping

| Mode | Behavior |
|---|---|
| **structural** (default) | group by Set, recursing into Sub-Sets at any depth; pages directly in the container fall to a trailing ungrouped band. (React's pipeline has no structural grouping today — net-new.) |
| **property** | bucket by value; **only** select / status / checkbox / date(time). Number, multi-select, url, relation, file, last-edited are **not groupable** (matches Swift). |
| **flat** | single group |

Property-grouping rules:
- **Status** buckets per option; default order is the status-group sequence (Upcoming → In Progress → Done) then option order within. `order_mode: "manual"` honors an explicit option-value `order` array (interleaving across groups — see Ideas fixture). Group header = the option rendered as its chip.
- **Select** buckets per option in schema order; manual order supported.
- **Checkbox** → Checked / Unchecked; a missing value routes to Unchecked (no separate empty bucket).
- **Date** bucketed by `date_granularity` (day `YYYY-MM-DD`, week ISO `YYYY-Www`, month `YYYY-MM`, year `YYYY`; default month).
- No-value bucket titled "No <Property>", placed per `empty_placement`, dropped by `hide_empty_groups`. Empty buckets (no items) are not rendered.
- 3 status groups are enum-locked both builds (EventKit mapping); options within are unlimited and orderable. Going past 3 categories is an agenda-side change, out of scope.

#### Sorting

Multi-key (full `sort[]` array, priority = array order — a **deliberate superset** of Swift's single-criterion pipeline; Nathan green-lit going above Swift), stable (ties hold input order), applied **within each group**. Type-aware extraction per `PropertyDefinition.type`:

- number → numeric · checkbox → false < true · date/datetime → chronological · select/status → **schema option order** (unknown → last) · multi-select → joined values · url → address.
- The comparator is **type-complete** like Swift's (relation/file extract to `''` → no-op tie; last-edited → date). `isSortable` (false for relation/file/last-edited) gates the Part-3 *picker*, NOT the Part-1 comparator.
- Reserved presets: Title (`_title`, case-insensitive), Created (`_id` = ULID order), Recent (`_modified_at`, created fallback).
- **Manual sort order is deferred** (grouping keeps its manual order; sorting uses option/type order for now).

#### Filtering

A **recursive** `FilterGroup` (a `rules` child is a rule OR a nested group) combined by `match` (all = AND, any = OR) → mixed AND/OR like `(A AND B) OR C`. Part 1 ports Swift's flat per-rule evaluator + per-type matrix (wider than the Part-3 picker); the recursion (nested groups) is net-new React, since Swift's `rules` are flat. The reserved `_modified_at` column filters as a date (`declaredType`→`last_edited_time`). Persisted `op` strings are Swift's **snake_case raw values** (on-disk parity): `is`, `is_not`, `contains`, `does_not_contain`, `is_empty`, `is_not_empty`, `greater_than`, `less_than`, `on_or_after`, `on_or_before`. Evaluator matrix by type — number: greater_than/less_than/is/is_not/is_empty/is_not_empty; date/datetime/last-edited: on_or_after/on_or_before/is_empty/is_not_empty; select/status/url/text: is/is_not/contains/does_not_contain/is_empty/is_not_empty; multi-select: same (membership); checkbox: is/is_empty/is_not_empty; tier relations `_tier1/2/3`: membership (is/is_not/contains/does_not_contain) + empty; user relation/file: presence-only (is_empty/is_not_empty; is/is_not no-op). A flat filter is byte-identical to Swift's; nested ones are React-ahead (Swift aligns later). The filter *editing UI* is Part 3.

---

### 5 — Default view minting

When a container's `views: []` is empty, synthesize a default Table view (Swift does this; React doesn't yet): `property_order = [_title, ...userPropertyIds]`, structural grouping, **Manual sort (page order)**, no `_modified_at` column. Tier columns appear via the default-on resolver rule. Minted in-memory on read; persisted on first user edit.

---

### 6 — Persistence (IPC + main)

Mirrors the existing sidecar + folds handlers, returning the `{ ok }` envelope (never throws across IPC):

- `views:save(containerPath, kind, view)` / `views:reorder` / `views:delete` — `kind` (`collection`|`set`) selects the sidecar (`_pagecollection.json` / `_pageset.json`); atomic writes preserving foreign keys; a `view_default` sentinel id gets a real `view_<ulid>` on first save.
- `activeViews:get` / `activeViews:set(containerId, viewId)` — the per-machine pointer file.
- `view:loadValues(containerPath)` — batch frontmatter read (§2).

Read and write stay cleanly separable (a HARD RULE): the value-load + resolver + pipeline are read-only; mutations are additive.

---

### 7 — Folder layout

`Detail/Table/` → `Detail/Views/`, mirroring Swift:

```
Detail/Views/
  Table/        (Part 2 — components)
  Gallery/      (later)
  pipeline/     filter · group · sort · column-resolver   (Part 1)
  columns/      (Part 2 — PropertyCellDisplay / PropertyCellEditor)
  settings/     (Part 3 — dropdown + panes)
```

Part 1 fills `pipeline/` + the shared/main data and IPC; the component folders are scaffolded empty.

---

### 8 — The seams Part 2 routes to

Stable outputs the Figma-designed UI consumes, so the table build never reaches back into the plumbing:

- **`ResolvedColumn[]`** — ordered `{id, kind}` descriptors (kind: title / property / tier / modified) honoring visibility. Column widths + the group/sort hoist are Part-2 render concerns.
- **`ResolvedGroup[]`** — ordered groups (header label + the value needed to render a status/select chip header), each with its sorted rows; structural groups nest.
- **Per-cell render data** — `(PropertyDefinition, PropertyValue)` per cell, plus resolved (icon, title) for relation/tier targets (Part 2 resolves these via the existing `Detail/Scope.ts` `findContext`).
- **Chips are direct components, built in Part 2** — created in `design-system/components/Chips/` (alongside `Popover`/`Segmented-Controls`/`menu`), built on React's existing chip styles (`tokens/chip.css.ts`). Select / multi-select / status share the one chip design via these components — **not** inline token `<span>`s, and **not** ported from Swift's `Components/Chips`.

---

### 9 — Out of scope (Parts 2 & 3)

Table/cell/chip components · inline cell editor (glass-control pickers for chip-types, plain inputs for number/url, a **"Calendar" placeholder** for date, native menus for simple actions) · the settings dropdown + panes · `display_as` box/chip/select variants (not modeled in React — status renders as the default chip for now) · view rename/duplicate/delete UI · `open_in` selector · **multi-select grouping** (multi-membership, deferred) · **manual sort order** (deferred).

---

### 10 — Verification

- **Pure units:** column resolver, each pipeline stage, status manual-order grouping, date bucketing, multi-key sort, recursive AND/OR filter, lenient decode — tested against the Swift behavior, with the synthetic `collection-with-status.json` as the conformance fixture.
- **Integration:** value-load IPC reads real frontmatter; `views:save` round-trips through the sidecar preserving foreign keys; active-view pointer persists per-machine.
- **Green bar for Part 1:** a hand-seeded view config renders real, correctly sorted/grouped columns with live property values — no settings UI required. Functional-green ≠ done; a UIX pass follows in Part 2.

#### Resolved (V2 review + Nathan)

1. Group/sort hoist — **render-time, in Part 2**; Part-1 column resolver stays verbatim. (§3)
2. Filter `op` strings — **snake_case**, evaluator matrix locked. (§4)
3. **Recursive AND/OR filters** + **multi-key sort** kept as deliberate supersets of Swift (Nathan: going above Swift is fine).
4. Both **Collection and Set views** handled by one container-relative path; Set views inherit the Collection schema; empty Sets appear (tree built from folders). (§2, §4)
