## View Filtering — Decision Log

### Frame

- **Purpose:** Author the view `filter` — the last blank ViewSettings/SettingsPane leaf — as the FilterPane, on the GroupingPane/SortingPane chassis.
- **Core Value:** Any view can express "show only the rows matching these rules," authored in-pane with per-type operators and value pickers, persisting to the sidecar the pipeline already honors.
- **Success Criteria:** A flat rule list with per-row And/Or filters the live table correctly for every filterable target type; a disabled filter dims/locks the pane without losing its configuration; files stay canonical (hand-authored filters still evaluate).

### Sources

- [[Views]] — pipeline order (columns → filter → group → sort); filter spec'd as "a recursive group of rules under Match All / Any"; Filter leaf listed Pending ("the gap is authoring it").
- `Pommora/src/shared/views.ts:69-81` — `FilterRule { property_id, op, value? (single string) }` + recursive `FilterGroup { match: 'all'|'any', rules }`; zod codecs `filterRule`/`filterGroup`; `SavedView.filter?` optional. No enabled flag exists.
- `Pommora/src/renderer/src/Detail/Views/pipeline/filter.ts` — the whole evaluator: 10 snake_case ops; per-type matrices; missing operand/value ⇒ no-op pass (a filter never excludes on what it can't apply); tiers = full id-list membership (`evaluateList`); context/file = presence-only (`evaluatePresence`); title = no-op pass; `_modified_at` via `modifiedStampString` (created_at fallback). Location: not filterable — the filter stage never receives `setTree`.
- `Pommora/src/renderer/src/Detail/Views/pipeline/resolveView.ts:26` — `applyFilter` runs first; nothing else consumes the filter config (no badge/toolbar count).
- `Pommora/src/renderer/src/Detail/Views/pipeline/filter.test.ts` — pins match modes, nesting, per-type semantics, no-op passes.
- `Pommora/src/renderer/src/Components/Detail/SortingPane.tsx` + `GroupingPane.tsx` — the chassis: PaneSlider hosting, ValueRow/PickerControl rows, `gp.middle` scroll cap, footing recipe, `saveViewAdopting` writes, `sortTargets`/per-type vocabulary pattern.
- `Pommora/src/renderer/src/Components/Detail/PaneSlider.tsx` + `menuSurface.css.ts:22` — panes shrink-wrap content above the 225px floor; **no max-width cap exists** — content-driven expansion is native.
- `Pommora/src/renderer/src/Detail/Views/PropertyEditing/PropertyPicker.tsx:63-71` — multi-value picks toggle and **stay open**; single-value picks dismiss. The stay-open chip picker already exists.
- `Pommora/src/renderer/src/Components/Chip.tsx` + `chip.css.ts` — removable chip variant: hover-reveal × on the right third, melt twins, `--chip-max` width cap. The hover-x chip-pill already exists.
- `Pommora/src/renderer/src/design-system/components/TextPicker/` — the outlined input precedent: 100–200px `field-sizing: content`, inset accent stroke on focus, eclipse overflow.
- `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx:535-540` — `contextOptionsFor`: tier/context option lists (id+title+color) from `tree.contexts`.
- Swift archive `FilterPane.swift` — the ancestor: All/Any picker over flat `[property][operator][value][−]` rows, per-type value editors, whole-group writes. Superseded on layout (no per-row And/Or there), kept for the per-type editor vocabulary.

### Decisions

#### A — Data Model

- **A-1:** [confirmed] The recursive `FilterGroup` stays the on-disk model, untouched in shape. The flat per-row And/Or UI serializes onto it: OR splits the flat list into AND-runs — `A and B, or C and D` ⇒ `{match:'any', rules:[{match:'all',rules:[A,B]},{match:'all',rules:[C,D]}]}`; an all-And list is a single `{match:'all'}` group. Descending order = the authoring order; precedence is managed by row order, never explicit sub-groups (Nathan's call).
- **A-2:** [assumed] The pane owns the `filter` slot wholesale **only for trees it can faithfully represent**, defined by SHAPE, never depth: exactly `{match:'all', rules: [leaves]}` or `{match:'any', rules: [(leaf | {match:'all', rules:[leaves]})…]}` — the two shapes the pane itself writes. Anything else locks — including shallow traps like an `any`-group nested UNDER an `all` root, which is only 2 deep but inexpressible flat. A locked tree still evaluates untouched (files canonical) and renders **dimmed as "hand-authored filter"** with an explicit Reset as the only action — never silently flattened: flatten-and-rewrite would change the filter's truth table without warning.
- **A-3:** [assumed] `FilterRule` gains `values?: string[]` for multi-operand ops (contains all / contains any / any-of chips); `value` stays for single-operand ops. **Core prerequisite, not an adjacency:** the `filterRule` zod codec is a strict object that STRIPS unknown keys on every save — the codec field (`values: z.array(z.string()).optional()`) and the evaluator's `values` reads land before any pane write can carry chips.
- **A-4:** [confirmed] Disable rides the **Matches row**: the pane's first row is `Matches: (Any / All / None)`, and **None is the disable state** — `MATCH_MODES` widens to `'all' | 'any' | 'none'` (no separate enabled flag). Three sites carry it, none optional: the zod enum (today an uncaught `z.enum(['all','any'])` — a bare widen without the codec change fails the WHOLE view's parse the first time the pane writes None), an explicit skip in `applyFilter` when the ROOT match is `none` (today `matchesGroup`'s binary `all ? every : some` would read `none` as OR), and root-only scope — a nested `none` is never pane-authored and evaluates as a pass (the no-op philosophy). Disable is **lossless by wrapping**: the live root becomes the single child of `{match:'none', rules:[<prior root>]}`, so the All/Any base mode and the full run structure survive verbatim; re-enable unwraps the child.
- **A-5:** [confirmed] Missing-operand ⇒ no-op pass stays — it's what makes a half-built pane row harmless to the live table while authoring.

#### B — Operators (new ops to add)

- **B-1:** [assumed] New op raw strings, snake_case like the rest: `starts_with` (text), `contains_all` / `contains_any` (multi-valued targets), `is_before` / `is_after` (strict date variants beside the existing `on_or_before`/`on_or_after`). `starts_with` is **case-insensitive**, matching `contains`' existing `toLowerCase` semantics.
- **B-6:** [confirmed] **Every new op is THREE coordinated changes, none optional:** (1) the `FILTER_OPS` registry entry — `evaluateRule` gates on `FILTER_OP_SET` *before* any per-type branch, so an offered-but-unregistered op silently shows all rows (looks applied, does nothing); (2) the per-type evaluator branch; (3) the per-op operand semantics, coded explicitly — the no-op-pass rule doesn't fall out of the natural implementation for every shape: `contains_all` as `.every()` passes an empty chip set for free, but **`contains_any` as `.some()` would EXCLUDE every row on an empty set** and needs an explicit empty-operand `return true` guard. Operand slot per op: `contains_all`/`contains_any` and multi-chip Is/Isn't read `values[]`; all single-operand ops read `value`.
- **B-7:** [confirmed] Date `is` compares at **calendar-day granularity — both sides truncated to the day** — never exact-ms equality (a stored `T14:30` timestamp must match its picked bare date). It's a new branch in `evaluateDate` alongside the empty-operand pass.
- **B-2:** [confirmed] Number adds `≥`/`≤` (`greater_or_equal`/`less_or_equal`).
- **B-3:** [confirmed] Date adds `is` (matches the calendar day).
- **B-4:** [confirmed] Operator labels use **Title-Case with contractions** throughout: Is · Isn't · Is Empty · Isn't Empty · Doesn't Contain · Isn't Checked.
- **B-5:** [confirmed] Single-valued Select/Status read **Is / Isn't / Is Empty / Isn't Empty** — no Is All (unsatisfiable with 2+ chips on a single-valued property; a page holds ONE select value). Multi-chips under Is / Isn't mean any-of / none-of. **Is Any / Is All / Isn't** belong to the array-valued types (Multi-Select, Context, Tiers). The any-of reading is itself **three coordinated changes** (the B-6 discipline): Select/Status Is/Isn't join the `values[]` operand readers; `evaluateText` gains an any-of/none-of branch (`values.includes(pageValue)`); and the chip picker's **commit shape** diverges from cell editing — it emits raw option-value strings into `values[]`, never a `multiSelect`/`context` PropertyValue.

#### C — Targets ("What")

- **C-1:** [confirmed] Schema properties by type (the SortingPane `sortTargets` pattern: real def icon, else type glyph), plus pseudo-targets.
- **C-2:** [assumed] **Title becomes filterable** — a real `title` branch in `evaluateByType` routing to the text matrix (`Is` / `Isn't` / `Starts With` / `Contains` / `Doesn't Contain`; no empty ops — a title is never empty). This **inverts a pinned test** (`filter.test.ts` pins `_title` as a Swift-parity no-op pass) — the pin restates to the new truth, deliberately.
- **C-3:** [confirmed] **Location** filters at **any depth** ("Is Inside" / "Isn't Inside" — a page in a nested sub-set matches its ancestor set). Rows carry only `parentSetId` and `SetTreeNode` has no parent pointers, so the evaluation **precomputes one descendant-id `Set` per Is-Inside rule per `applyFilter` call** (the existing `subtreeIds` walk) and membership-tests `parentSetId` — never an O(depth) ancestor walk per row (the "never on every X" rule). `setTree` is already in `resolveView`'s scope; it threads into `applyFilter`. A rule naming a set id absent from the tree is a **no-op pass** (the dead-property philosophy — a filter never excludes on what it can't apply); the rule row renders by its raw id (the Sorting dead-criterion precedent).
- **C-4:** [assumed] **Modified** rides the date matrix (already evaluates). **Created** deferred to match the Sorting pane's Title + Modified vocabulary.
- **C-5:** [confirmed] **Tiers** (Areas/Topics/Projects) already evaluate full membership — the pane exposes them with the tier labels + context chip pickers.
- **C-6:** [confirmed] **User context properties** upgrade to tier-style membership (full Is Any / Is All / Isn't). The evaluator's shared `case 'context': case 'file':` presence arm **splits** — context reroutes to `evaluateList` (its value is genuinely a ULID array), file stays presence-only — and the pinned no-op test for user relations restates to membership.
- **C-7:** [assumed] **File** stays presence-only ("Has File / No File") for v1; name-contains → Prospects.
- **C-8:** [confirmed] The Tier/Context **chip pickers need the contexts lists** (`tree.contexts.areas/topics/projects`), which no chassis pane receives today (`{source, view, schema, label, onBack}` only). The SettingsPane host already subscribes `st.tree`; **ViewSettings pulls only `st.load` and needs its own `tree` subscription** — both doors thread the contexts into the FilterPane, the `contextOptionsFor` pattern.

#### D — Pane UI (Nathan's design, from his brief)

- **D-1:** [confirmed] Row = `(What)(Operator)(Value)`; rows 2+ lead with an **And/Or double-chevron toggle**. The value slot is omitted where the operator is self-contained (checkbox is checked / isn't checked; is empty / is not empty).
- **D-2:** [confirmed] Each slot is an individual **outlined input field** (TextPicker stroke recipe) with its own overflow mechanics, standard row-overflow otherwise.
- **D-3:** [confirmed] The pane **expands beyond the standard pane width to its own max**, driven by its longest row. Native to PaneSlider (no cap exists); the FilterPane sets its own max-width knob so it can't run away.
- **D-4:** [confirmed] Value pickers: text-based display for non-chip types; a **chip picker that stays open** for multi input; chips size down to fit the field (`--chip-max`); **Status picks render as chip-pills with the hover-× remove**. Seam note: PropertyPicker's `multi` mode governs BOTH stay-open behavior and commit shape (it hard-commits `multiSelect`/`context` PropertyValues) — the filter's chip fields therefore run a **filter-owned picker host**: same PickerMenu + chip options + stay-open toggling, but committing raw option-value strings to the rule's `values[]` (→ B-5), never routing through PropertyPicker's cell-editing commit.
- **D-5:** [confirmed] Disabled state: the pane **dims and locks** (ghost opacity + inert), preserving every row.
- **D-6:** [confirmed] Drag-to-reorder rows: out of scope unless it falls out trivially. Add/remove rows only.
- **D-7:** [confirmed] The visual design is ratified in-log (→ section F), built entirely from the existing pane vocabulary; exact pixels stay in the code's knobs, per convention.
- **D-8:** [confirmed] The **Matches row** is the enable/disable control (→ A-4). Rule rows sit **indented** under it; each carries its And/Or connector as a footnote-emphasized trailing-option field with an inside double-chevron (`And<>` / `Or<>`).
- **D-9:** [confirmed] **Uniform column geometry**: the rule region is one CSS grid — `[connector][what][operator][value]` — so columns align across rows with no per-row measuring. Fields expand to the longest row's needs; the Operator column stays compact (sized to its widest label); spare and short space bias the leading (What) and trailing (Value) fields — under pressure the Operator truncates into its eclipse fade first.
- **D-10:** [confirmed] The **Matches picker is the global mode; per-row chevrons are overrides** — a row whose connector matches the mode sits at the default, a flipped chevron deviates (starting or joining an AND/OR run). When connectors are mixed the Matches picker reads **All** ("Or" is a valid deviation under All). Serialization is unchanged — the connector sequence still derives the any-of-all-runs tree.

#### F — Visual Recipe (the in-chat Figma, ratified)

- **F-1:** [confirmed] Chassis: `MenuPaneTopRow` breadcrumb · the **Matches** lead row (a `flushTrailing` MenuItem, **no leading icon**, trailing PickerControl All/Any/None in the `gp.pickerTone` treatment) · flush separators · the rule region in the `gp.middle` scroll sandwich (`overflow-eclipse-y`) · a footer action row that is **a bare "+"** (no label).
- **F-2:** [confirmed] Fields wear the `interactionField` recipe (the quinary-fill rounded surface) at **control size, `label.control` tone throughout**, focus lighting the inset accent stroke at tint-secondary (the TextPicker recipe). What/Operator are trigger fields popping beaked PickerMenus with the inside `chevrons-up-down` glyph; the What field **shows the property's icon inside the field** (def icon, else type glyph — the `sortTargets` pattern).
- **F-3:** [confirmed] The And/Or connector is a mini field of the same recipe in the `gp.subLabel` tone (footnote-emphasized, secondary) with the inside double-chevron; **click toggles directly** (two states, no menu). Its presence indents rows 2+; row 1 renders none and the grid holds alignment.
- **F-4:** [confirmed] Value fields per type — **chips** (Select/Status/Multi/Context/Tiers) render inside the field at the `gp.subChip` step-down, opening the stay-open PropertyPicker; Status as `chipPill` with the hover-×. **Text/Number/Link/Title** use the `textPicker.input` recipe (field-sizing between floor and cap, internal scroll behind the eclipse). **Date** shows the value in the **property's assigned date format** (the view's `column_styles` formats; default format when unstyled) and opens the CalendarPicker. **Checkbox and the empty ops** render no value field — the operator carries the clause.
- **F-5:** [confirmed] The checkbox Operator options lead with a **checkbox glyph — empty for Isn't Checked, checked for Is Checked — the checked one tinted the def's `checkbox_color`** (absent = system accent, `properties.ts` def-level key).
- **F-6:** [confirmed] Row removal is a **hover-revealed trailing ×** per rule row (the chip-× reveal pattern at row scale); rows stay clean at rest.
- **F-7:** [confirmed] Matches = None dims the rule region to `var(--state-ghost)` with pointer-events inert while the Matches row stays live; a fresh "+" row seeds placeholder-tone fields (`label.tertiary`) and is a harmless no-op pass until completed (A-5).
- **F-8:** [confirmed] Pane width rides PaneSlider's native content shrink-wrap above the 225px floor, capped by a pane-local `FILTER_MAX_WIDTH` knob.

#### E — Adjacencies

- **E-1:** [assumed] `filter.test.ts` grows matrices for every new op + title + location; `views.test.ts` pins `values`/`enabled` round-trips.
- **E-2:** [assumed] [[Views]] Filter bullet + Surfaces section restate to the shipped truth on close; the Pending "View-Settings Editing Panes" entry drops the Filter line.
- **E-3:** [open] A filter-active indicator (toolbar badge/count) — nothing consumes the filter config today. Prospect unless Nathan wants it in v1.
- **E-4:** [assumed] Open pickers (CalendarPicker is uncontrolled after mount) **dismiss on a view switch** — a mid-edit switch never strands a picker writing into the wrong view.

### Core (must-have)

- The FilterPane on both doors (SettingsPane Filter leaf + ViewSettings), flat rule rows with And/Or, per-type operator vocabularies, per-type value editors (text · number · date · option chips · context chips), add/remove rows, enable/disable dim-lock, wholesale slot writes via `saveViewAdopting`, evaluator extensions (new ops, title, location, `values[]`, `enabled`).

#### Prospects (allowed later, not now)

- File name-contains filtering — needs a fileLabel-based text matrix; don't-foreclose: keep `evaluatePresence` a thin switch.
- Toolbar filter-active badge / filtered-count — nothing reads the config today; don't-foreclose: none needed.
- Created as a filter target — mirrors Modified's reserved-id path when wanted.
- Row drag-to-reorder — precedence is order-sensitive, so it's a real want; groupingDnd is the chassis when it comes.

#### Out of Scope (won't do)

- Explicit nested sub-group authoring UI — Nathan's flat-with-descending-precedence design deliberately replaces it; the data model keeps nesting for hand-authored files.
- Filtering for non-Table renderers' own surfaces — arrives with those renderers.

#### Considered & Rejected

- Match All/Any as the ONLY conjunction control (the Swift FilterPane + original spec wording) — rejected for per-row And/Or connectors; the Matches header row survives as All/Any/None (None = disable), the global mode the per-row chevrons override (D-10).
- Per-row connectors as the sole authority with Matches as a bulk-set — rejected for the mode-plus-overrides reading; the mode gives new rows their default and the mixed state a stable display (All).
- A separate `enabled` boolean for the disable state — rejected; `match: 'none'` carries it on the existing field.
- Encoding multi-operands into the single `value` string (delimiter) — rejected for `values?: string[]`; option values may contain any character.
