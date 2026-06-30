## Table Views — Part 2 (Table UIX Redo + Label Fix) — Decision Log

> Status: **Ratified — V3** (V2 review-folded + finalized; V3 folds Nathan's pre-implementation additions: horizontal scroll, tiers default-on + in Visibility, sidebar chevron-DRY disclosures, ghosted reorder drags, hide/show collapse animation, persistence-across-hide/view hardening). Predecessor: `superpowers:brainstorming`. Successor: `writing-plans`.

### Frame

- **Purpose:** Replace the Part-1 throwaway `TableView` stub with the real Part-2 Collection/Set table — type-aware cells, id→name resolution everywhere, grouping presentation — designed fresh + DRY.
- **Core Value:** A table that shows human-readable names everywhere (zero raw IDs) with type-aware cells, non-inhibiting (never blocks selection/scroll).
- **Success Criteria:** No raw ULID / reserved-id / stored option-value ever reaches screen; select/status/checkbox render as chips; tiers render as resolved Context links; structural + property group headers show resolved names; clean read-only table.

### Sources

- `src/renderer/src/Detail/Views/Table/TableView.tsx` — the Part-1 stub; renders `c.id` / `g.key` raw — the leak site. Consumed only by `ContainerView.tsx`.
- `src/renderer/src/Detail/Views/pipeline/*` — pure pipeline (columns/filter/group/sort/value); already ID-addressed, merged + green.
- `src/shared/views.ts` — `SavedView` shape; property-ID addressed throughout.
- `src/shared/properties.ts` — `PropertyDefinition` (carries `name`), `RESERVED_PROPERTY_ID`, `selectColor` (Notion's 11-color palette); user `relation` retired (tier-only).
- `src/shared/types.ts` — `NexusLabels`, `ViewRow` / `ResolvedColumn` / `ResolvedGroup`, node shapes (`PathNode.title`), `tree.contexts.{areas,topics,projects}`.
- `src/main/properties/tiers.ts` — `mergeTierProperties` (dormant) + `tierPlural` seam.
- `src/main/settings.ts` — `settings.json` shape; `labelsToDisk`.
- `src/renderer/src/design-system/tokens/chip.css.ts` — `chip` / `chipColor` / `chipLabel` / `chipCheckbox` tokens — the DRY cell surface for pills.
- [[Resources/II. Pommora/II. Features/Views]] — canonical view spec; "Rich Table Cells" listed Pending.
- [[Resources/II. Pommora/II. Features/Connections]] — `[[ ]]` connections are body-only, **never** table columns.

### Decisions

#### A — ID→Name Resolution (the foundational fix)

- **A-1:** [confirmed] The leak is render-only — the pipeline is already ID-addressed. The fix resolves ids→names at draw time; the data model does not change.
- **A-2:** [confirmed] One renderer-side resolver covers every id, fed the resolution context (A-4): property name ← `schema` `def.name`; **tier label ← `tierLabel(level, tree.labels)`** (renderer-side, from B's `area`/`topic`/`project` labels — NOT the main-only `mergeTierProperties`, which can't cross the process boundary); Set name ← tree; option `value`→`label` ← the property def; Context ULID→`{title,color}` ← `tree.contexts`.
- **A-3:** [confirmed] DRY: design fresh, reuse the chip tokens + a single resolver. One `TableView` (consumed by `ContainerView`) fixes every Collection/Set table.
- **A-4:** [confirmed] **Resolution context — the plumbing A needs (the review caught the stub passes none of it).** Cells AND group headers receive `{ schema, contextsById (ULID→{title,color}, built once from `tree.contexts`), labels }`. The stub today renders raw `c.id` / `g.key` with no schema/tree/labels in scope (`TableView.tsx:32,84,102`), so resolution is impossible as-written. The new cell + header components take this bundle — the single dependency that makes A real.

#### B — NexusLabels Restructure (prerequisite)

- **B-1:** [confirmed] All three tiers become first-class `LabelPair`s (singular + plural): `area`, `topic`, `project`. Swift is PAUSED — no cross-build reconciliation; we own the on-disk shape and may evolve it (keeping it clean + portable).
- **B-2:** [confirmed] **A** — drop `sidebarSections`; derive sidebar headers from `area.plural` / `topic.plural` / `pageCollection.plural`. One source per label.
- **B-3:** [confirmed] Migration: existing `settings.json` → tier `plural` from old `sidebar_sections.{areas,topics}` (and `project` already a pair); `singular` defaults to "Area"/"Topic".
- **B-4:** [confirmed] B is end-to-end wiring, not just the type: add `area`/`topic` to `NexusLabels` (`types.ts`), the write path (`labelsToDisk`, `settings.ts`), and the **read path into `tree.labels`** (`readLabels` in `readNexus.ts` — the review confirmed it doesn't parse them yet), plus B-3's migration. Without the read-path the labels are orphaned on disk and never reach the renderer, which `tierLabel` (A-2) depends on.

#### C — Design Source + Surface

- **C-1:** [confirmed] Design fresh — no Swift table to port (the SwiftUI custom-table was abandoned). Reuse the Pommora design system + chip tokens.
- **C-2:** [confirmed] **Build in the actual code** — the real `TableView` + cell components, iterated in the live dev app (HMR / screenshots). No separate design surface (Nathan reversed the showcase-leaf idea — the real app IS the surface, most DRY). Toggles surface later as Layout-pane options.

#### D — Row Ordering (paradigm core)

- **D-1:** [confirmed] Order mechanism already exists + is Swift-ported: `resolveOrder` (`order.ts`) + `page_order` sidecar array + `setChildOrder('page_order', ids)` (`crud/reorder.ts`). Default (no persisted order) = creation order (ULID-ascending). Table row-drag reuses this seam — not new plumbing.
- **D-2:** [confirmed] **No sort, no group** → rows in `resolveOrder` order; drag reorders freely → `setChildOrder('page_order', …)`. Canonical manual order.
- **D-3:** [confirmed] **Sort active (single key)** → sort is primary; drag is clamped to within an equal-sort-key run (can't cross a sort boundary). **2+ sort keys → manual reorder is disabled entirely** (no handle): within-run nudging under a multi-key sort is a headache the sort should just own. Cross-group drag (property reassignment) is unaffected.
- **D-4:** [confirmed] **Group active** → within-group drag reorders; cross-group drag **mutates the grouped property** to the destination group's value (e.g. Open→Done group writes `Status=Done`).
- **D-5:** [confirmed] **Two-home model.** Canonical `page_order` (entity sidecar, portable) is the no-sort/no-group order only. Sorted/grouped-with-sort nudges go to a **separate per-machine `.nexus/` order cache** — a NEW file following the folds *pattern* (`activeViews.json` / `tableHeadingColumns.json` store selection/UI-state, not order; this store is new), **keyed by view id**, so the portable filesystem order never moves. Both use `resolveOrder` tolerance (stray/tombstone ids drop harmlessly). Chosen over a synced `SavedView` field (sync churn) and over one shared `page_order` (pollutes the portable order).
- **D-6:** [confirmed] **The cache can never override the real sort — two safeguards:** (1) it's applied strictly as the *lowest-priority* comparator (after every real sort key), so it only reorders rows already equal on all sort keys; (2) the drag is clamped within an equal-sort-key run, so a conflicting move can't even be attempted. The sort sorts by exactly what it's told; the manual layer fills only the gaps.
- **D-7:** [confirmed] **Group reorder (distinct from row reorder).** A handle on the group header/label drags a whole group to a new position, carrying its child rows. **Property grouping** → writes `GroupConfig.order` + sets `order_mode: 'manual'` on the SavedView (synced view config; the pipeline's `bucketOrder` already honors manual). **Structural (Set) grouping** → writes the container's `set_order` sidecar (canonical, the Set analog of `page_order`; already wired in `readNexus`). Orthogonal to D-3…D-6 — it's the group-by axis, so the multi-sort disable doesn't apply. PommoraDND vertical `SortableZone` over the headers; separate target from the left-gutter row handle. The **scope asymmetry is intentional** (mirrors D-2/D-5): `set_order` is canonical, **shared across every view** of the container; `GroupConfig.order` is **view-scoped**.
- **D-8:** [confirmed] **Sorted + grouped compose, they don't conflict (D-3×D-4):** a drop into a *different* group = reassignment (D-4, writes the property); a drop *within* the same group = reorder clamped per D-3/D-6 (off if 2+ sort keys). Where you drop disambiguates — no extra rule needed.

#### E — Must-Haves (interaction surface)

- **E-1:** [confirmed] **Hide Property** — right-click a column header → menu → writes `hidden_properties`; un-hide via the Part-3 Visibility pane. Tier columns (Areas/Topics/Projects) are **default show = on** (the resolver's default-on tiers) and also appear in the **Visibility pane** for show/hide, like any column.
- **E-2:** [confirmed] **Column reorder** — drag a header (PommoraDND horizontal `SortableZone`) → commits `property_order`; the whole column shifts live with a **ghosted** dragged column (the lifted column rendered ghosted while neighbors open the gap) — modeled on the MarkdownPM table drag.
- **E-3:** [confirmed] **Row drag** — left-gutter handle (PommoraDND vertical `SortableZone`), MarkdownPM feel via the SAME engine (the CM6 table extension itself is not reused — wrong layer). Same **ghosted** lifted-row effect as MarkdownPM's table rows. Persists per D-2…D-5.
- **E-4:** [confirmed] **Disclosures** — Set / Sub-Set / Collection group headers are chevron disclosure rows; collapse driven by `collapsed_groups` (built); reuse the **sidebar's** chevron disclosure animation (the same chevron-rotate + collapse, DRY — no new motion).
- **E-5:** [confirmed] **Layout pane (Part 3)** — `Format: Table ›` (view-type picker, inert until other renderers exist) + **Hide Page Icons** + **Hide Borders** toggles (reuse the built `Switch`). Two new `SavedView` fields: `hide_page_icons?`, `hide_borders?`.
- **E-6:** [confirmed] **Link (URL) cells** — inline; empty → single-click edits; filled → single-click opens, double-click edits inline.
- **E-7:** [confirmed] **Date cells** — render a stub now (real picker deferred).
- **E-8:** [confirmed] **Title cells** — double-click empty space in the column → edit; right-click the title label → rename menu.
- **E-9:** [confirmed] **Icon** — right-click → existing `IconPicker`.
- **E-10:** [confirmed] **Inline edits commit on Enter or blur, cancel on Escape** (the inverse the review flagged) — title and link cells alike. A filled URL's single-click **opens in the system browser** (external).
- **E-11:** [confirmed] **Hide/show column animates** — hiding collapses the column in, unhiding expands it out, on an **existing motion token** (a `--duration-*` + `--ease-*` alias, e.g. the `disclosure` duration), never a new keyframe.

#### F — Drag Engine Truth

- **F-1:** [confirmed] PommoraDND is the one engine behind `interactions/drag.tsx`, explicitly supports `layout: 'table'`, same measure-once / decide-then-animate feel. Column + row reorder are horizontal/vertical `SortableZone`s. The MarkdownPM table drag is CodeMirror-coupled and NOT imported — the feel is identical because the engine is the same.

#### G — Cell Taxonomy

- **G-1:** [confirmed] **Reserved columns.** Title = icon (hidden per *Hide Page Icons*) + title, emphasized primary column; single-click opens, double-click empty space → inline edit, right-click label → Rename / Edit Icon, icon right-click → `IconPicker`. Tiers = linked Contexts as **ContextChips** (G-4), one per Context, tinted by the Context's color, click opens the Context (resolved ULID→title via `tree.contexts`). Modified = formatted timestamp, read-only.
- **G-2:** [confirmed] **Property columns.** select / status → one `<Chip>`; multi_select → several `<Chip>`s, each `chipLabel`-capped; checkbox → `chipCheckbox`; url ("Link") → colored inline link (empty→single-click edit, filled→single-click open / double-click edit); date/datetime → stub; number → plain text (left-aligned v1).
- **G-3:** [confirmed] **New DRY surfaces (one source each):** a single `<Chip>` component wrapping the chip tokens (reused by cells AND the PickerMenu); one `selectColor → chipColor` map (Notion 11 → chip palette 11; brown/pink/indigo nearest-color, tunable); one `tierLabel(level, labels)` helper; reuse of `resolveOrder` / `setChildOrder`.
- **G-4:** [confirmed] **ContextChip** (`Components/ContextChip.tsx`) — a deliberately-isolated thin wrapper over `chip` + `chipColor`: background overridden to `color.fill.quaternary` (the neutral 6% grey = the `--input-field` token) instead of the colored `tint-primary` (60%), radius `8px` instead of the pill `10px`. Keeps the colored border + text. Reads as a reference/link surface, distinct from the saturated property chips; its own component so it's trivially swappable.

#### H — Table Structure & Layout

- **H-1:** [confirmed] **One header row per table** (never repeated per group) + **one shared column-width set** table-wide. Disclosed groups are body sections under the single header — no per-group `<thead>`. The table container **scrolls horizontally** (overflow-x) when total column width exceeds the pane (Q-4); the header scrolls with the body (no sticky, per Q-5).
- **H-2:** [confirmed] **Column resize** by dragging the column edge; persists to `column_widths` (already on `SavedView`). **Persistence is load-bearing — the known Swift failure mode:** column order (`property_order`) + width (`column_widths`) must write to the correct `SavedView` fields and **survive hide/show toggles AND view switches**, verified by tests — Swift's reorder/resize drags silently failed to register to the right data, the exact bug this guards against.
- **H-3:** [confirmed] **Unlock banner + title.** Revert `.detail-locked` for the three content-views that use it (collection/set/context, via `DetailScaffold`'s `lockedHeader` flag — NOT page detail) so banner+title scroll WITH the content like a page. (Reverts an earlier Nathan direction.)
- **H-4:** [confirmed] **Keep the current cell end-gutter** — the existing cell edge padding reads right; preserve it.
- **H-5:** [confirmed] **Row drag handles live in the gutter, hover-revealed per row** (MarkdownPM behavior) — visible only over the hovered row.
- **H-6:** [confirmed] **Header-row dividers** = thin vertical segments with top/bottom padding (shorter than full row height).
- **H-7:** [confirmed] **Grid + hairline styling.** Table grid lines route to the **`separator.border` color token** — no hardcoded hex (the stub's `#FFFFFF1A` / `#FFFFFF0D` go away). Every hairline divider line-element gets **rounded caps** (`border-radius` pill ends), never a sharp-cornered rectangle — matching the Segmented-Controls + MarkdownPM separator treatment.

#### I — Column Widths

- **I-1:** [confirmed] One DRY width table → each column type maps to `{ min, default, max }`: Title, Status, Select, Checkbox, Link (url), File, Multi-Select, Contexts (tier), Created At, Modified At, Date & Time, Number — with a fallback for any unlisted type.

#### J — Spacing & Padding (DRY sources)

- **J-1:** [confirmed] Cell **X and Y padding** are single DRY sources (not hardcoded per cell).
- **J-2:** [confirmed] Two DRY **inter-section gap** paddings around a disclosure-interrupted grid: one for **root-level** disclosures (Sets), one for **nested Sub-Sets**.
- **J-3:** [confirmed] **Per-layer indent (DRY).** Each nesting level adds one DRY indent unit to the **title cell + disclosure header** left padding, scaled by depth (`Set` / `>Page` / `>Sub-Set` / `>>Page` — a Set's page = 1, a Sub-Set = 1, its page = 2). The indent lives *inside* the title column, so column boundaries stay aligned table-wide (Q-6).

#### K — Sizing & Typography

- **K-1:** [confirmed] **Table Size: Standard | Compact** routes DRY typography (+ density). No user control yet — reserve one for the full ViewPane/Layout pane (comment it). **Default = Compact.**
- **K-2:** [confirmed] Type scales with size — row = the size's standard weight, disclosure header = its emphasized: **Compact** (default) = row `callout` / disclosure `callout-emphasized`; **Standard** = row `body` / disclosure `body-emphasized`.

#### L — Disclosure Group Rendering

- **L-1:** [confirmed] **Status** group glyph = always **display-as pill** (ignores the property's capsule/checkbox `display_as`).
- **L-2:** [confirmed] **Checkbox** group = glyph + state — `[*] On` / `[ ] Off`. (On/Off become user-namable via the checkbox edit pane later — route disclosure titles to those names when it lands; pending that feature.)
- **L-3:** [confirmed] **Date & Time** group = property icon + bucket label (month/year/day…), in `callout-emphasized`.
- **L-4:** [confirmed] **Select** group = the option's glyph/chip.
- **L-5:** [confirmed] Disclosure headers get a **hover-revealed `label-secondary`** affordance + a **"+" button pinned right** (to a padding var) that **creates a new page at that group's root, sorted to bottom**, via a `newItemsTo(): 'top' | 'bottom'` helper — **default 'bottom'**, no caller yet (comment it as pending a caller).

#### M — Display-As Awareness

- **M-1:** [confirmed] **Model `display_as`** in `PropertyDefinition` (today it rides through unread) so **cells + the picker render per the property's `display_as`** — date/time + status now; **checkbox "display as switch" pending** (the `Switch` primitive exists). The render forms all **already exist as chip variants** (`chip.css.ts`: pill / select / checkbox) — nothing new to design; the **Display-As toggle UI** that switches them is a **ViewPane-pass** concern, not this table work. Disclosure overrides (L-1…L-4) still win in headers. **Unknown/absent `display_as` → the *type's* default render** (status→pill, select→chip, checkbox→glyph, date→stub) — never a blanket "pill". Tiers carry **no `display_as`** — the ContextChip (G-4) is their unconditional render.
- **M-2:** [confirmed] **Pages show their icon by default** — `hide_page_icons` defaults false.

#### N — Reserved Columns & File Cells (decided minors)

- **N-1:** [confirmed] **Created At** becomes a first-class reserved render column (formatted date, read-only) like Modified At — `_created_at` has no render branch today; add one.
- **N-2:** [confirmed] **File cells** render the file name(s) as inline link(s) (the `file` PropertyValue is a path list).

### Resolutions (the raised questions, settled)

- **Q-1:** [confirmed] Multi-select grouping is NOT added — `multi_select` stays non-groupable. Disclosure glyphs are **Select-only** (L-4); no pipeline change.
- **Q-2:** [confirmed] Typography settled — see K-2 (Compact = callout / callout-emphasized; Standard = body / body-emphasized; default Compact).
- **Q-3:** [confirmed] `display_as` render variants **already exist as chip forms** (`chip.css.ts` — pill `chip`, select pill+icon, checkbox `chipCheckbox`); cells render per `display_as` using them — nothing new to design, just wiring. Unknown/absent `display_as` → the **type's default** render (M-1). The **Display-As toggle control** (switching a property's `display_as`) is afforded to the **ViewPane pass**, not this table work.
- **Q-4:** [confirmed] **No auto-fill.** Columns size to their `{min, default, max}` (+ resize). Cell content past the column width **ellipses with the chip overflow logic** — ellipsis at rest, hover-scrolls within the cell, drops the ellipsis on hover (the `chipLabel` behavior generalized to every cell, a DRY reuse). Total > pane → horizontal scroll; < pane → trailing space.
- **Q-5:** [confirmed] **No sticky column header** — it scrolls away with the banner/title (one scroll).
- **Q-6:** [confirmed] Nested levels indent the **title cell + disclosure header** by depth (J-3); the indent sits *inside* the title column, so column boundaries stay aligned table-wide (rows never shift out of column).
- **Q-7 + Q-9:** [deferred] The page-**creation affordance** (the flat-table "+", and new-page-into-a-property-group) is pending Nathan's own solution — not specced this pass. The per-group "+" (L-5) stands as the shape.
- **Q-8:** [confirmed] **No no-value band header** — no-value rows render as **normal rows** (their other cells populated) in a headerless band (the existing `ungrouped` kind); only the *grouped* property's cell is empty. Placed per `empty_placement`.

### Core (must-have)

- The ID→name fix (A), the NexusLabels restructure (B), the row-ordering model (D), and must-haves E-1…E-9 + disclosures.
- Cell taxonomy (G): title · select/status/multi-select chips · checkbox · number · url/link · date-stub · tiers-as-ContextChips · modified.

#### Prospects (allowed later, not now)

- Cover/banner display; the Board / List / Cards / Gallery renderers; the real date picker (date cell is a stub now). Column resize moved to must-have (H-2).

#### Considered & Rejected

- Hardcoding tier column labels ("Areas/Topics/Projects") — plants the exact "too obvious to care" bug; rejected for settings-sourced resolution via one `tierLabel()` helper.
- A per-view `row_order` on `SavedView` — rejected; order is filesystem-canonical (`page_order` sidecar), shared across views, not view-scoped.
- Separate design surfaces (throwaway HTML; the design-system showcase leaf) — both rejected; the table is built in the actual app code (H-1/C-2) — most DRY, zero re-implementation.

#### Review

- [x] Adversarial review run as three dispatched read-only agents (compile-grounding + logic/coverage + UIX→data), per `rules/Review-Discipline.md`. **Compile-grounding: clean** (every code claim held). Logic/coverage + UIX→data findings folded → V2: the resolution-context plumbing (A-4), renderer-side tier resolution (A-2), read-path wiring (B-4), sorted+grouped composition (D-8), per-type `display_as` fallback (M-1), inline-edit commit/cancel (E-10). Ratified after the fold — a second round would re-confirm ground the agents already verified by `file:line`.

#### Lessons

- Swift is paused; the `settings.ts` "Swift-compatible" machinery is no longer a live constraint — the on-disk shape is React's to evolve (keep it clean + portable, not frozen).
- "Resolve ids→names at render" is a hand-wave until the **resolution context** (schema + contextsById + labels) is explicitly threaded into the cell/header components — the review caught the stub passes none of it. A render-resolution decision must name its data dependency, or it can't be built.
- Tier-name resolution belongs in the **renderer** (`tierLabel` from `tree.labels`), not the main-only `mergeTierProperties` — naming a main-process function from a renderer resolver is a process-boundary bug the UIX→data pass exists to catch.
