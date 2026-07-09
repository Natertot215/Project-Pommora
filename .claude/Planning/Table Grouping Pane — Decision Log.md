## Table Grouping Pane — Decision Log

### Frame

- **Purpose:** Build the Grouping leaf — the pane (reached from SettingsPane's Group entry and ViewSettings' Group leaf, both currently blank) that authors a table view's group config: Group By, Order, Sub-Group (location only), the group-order preview/reorder list, and the Ungrouped placement toggle.
- **Core Value:** A user can change how a table groups — location or property — and control group order, entirely from the pane, with the table updating live.
- **Success Criteria:** Every groupable config the pipeline already honors from the sidecar is authorable in the pane; location order mode round-trips to the filesystem when told to; nothing in the pane can write a config the pipeline can't render.

### Sources

- [[Views]] — the pipeline (columns → filter → group → sort), saved-view model, "Group/Filter/Sort open blank leafs"; group config semantics (structural/flat/property, group_order, manual band order).
- [[TableView]] — Groups rendering, band drag semantics (view-owned manual order, cross-tree drops touch fs), the ungrouped flattened tail w/ no "None" band, `empty_placement` currently decode-parity-only, group-header "+" (inert, pending design).
- `src/shared/views.ts` — `GroupConfig` union (structural | flat | property w/ `order_mode: configured|reversed|manual`, `order`, `date_granularity`, `empty_placement: top|bottom`, `hide_empty_groups`), `SavedView.group_order`, `collapsed_groups`. Verified directly.
- `src/renderer/src/Detail/Views/pipeline/group.ts` — GROUPABLE = select/status/checkbox/date/datetime; `bucketOrder()` (manual → configured → reversed); ungrouped tail pinned last; structural recursion; fallback-to-structural on unmappable property.
- `src/renderer/src/Detail/Views/pipeline/bandOrder.ts` — `orderGroups()` applies `group_order` to structural bands only.
- `src/renderer/src/Detail/Views/Table/bandDndModel.ts` + `GroupHeader.tsx` — band-drag order math, chip/glyph group headings (status→pill, select→label chip, checkbox glyph, datetime icon+label), hover "+".
- `src/renderer/src/Components/Detail/SettingsPane.tsx` + `ViewSettings.tsx` — the two doors; Group renders `blankLeaf` today; PaneSlider min 225×245.
- `src/renderer/src/design-system/components/menu/Menu.tsx` + `menu.css.ts` — MenuItem / MenuPaneTopRow / MenuBottomRow / MenuScrollFrame, `footingLabel`/`footingSymbol` footing typography.
- `src/renderer/src/Components/Detail/HiddenPane.tsx` + `LayoutToggles.tsx` + `PropertiesPane.tsx` — built-pane structural templates (scroll frame, footer toggles, drag regions).
- Figma (screenshotted live) — three Grouping pane variants: Location (hierarchy + Flatten/Hide Location toggles), Status/Descending (chips under group headings), Status/Custom (flattened Options chip list).
- `src/renderer/src/design-system/components/OverflowScroll.tsx` + `.css` — the DRY'd scroll-edge fade (`overflow-eclipse` / `-y` mask, `--eclipse-fade` knob); the pane's middle region wears the vertical variant.
- `src/renderer/src/design-system/components/Reveal.tsx` — grid-row disclosure primitive (mount/unmount on the shared disclosure motion); the Group By pane-swap vehicle.
- `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts` + `src/shared/columnStyles.ts` — `formatDate()` + the per-view date/time/weekday format families; date group headings resolve through these.
- `src/main/contextMenu.ts` + `src/preload/index.ts` — the native-menu IPC family the footing value-pick menus extend.
- `src/renderer/src/Components/Detail/paneDnd.tsx` + `paneDndModel.ts` — in-pane drag orchestration (RowShell/regions/slots) the hierarchy + Custom chip lists reuse.
- Swift archive: `Features/ViewSettings/GroupingPane.swift`, `GroupingOptionsList.swift`, `Domain/Collections/SavedView.swift`, `GroupResolver.swift` — the disclosure-picker precedent, the on-disk GroupConfig parity shape, the status grouped-preview, the empty-group footer. Swift never had Location order mode, the structural Ungrouped toggle, or Sub-Group — those are React-first.

### Decisions

#### A — Pane Placement & Chrome
- **A-1:** [confirmed] The pane is the Group leaf behind both doors — SettingsPane's Group entry and ViewSettings' Group leaf — one shared component, like Visibility. Header = MenuPaneTopRow (`< Settings` / `< back` + "Grouping" breadcrumb).
- **A-2:** [confirmed] Table-specific: this pane is the TABLE grouping editor; other view types get their own grouping surfaces later (Nathan: calendar/gallery/timeline "mechanically need different grouping mechanisms"). The component keys off view type.

#### B — Group By & Order Rows
- **B-1:** [confirmed] Value rows at top — `Group By:` and `Order:` — each with the double-chevron (`chevrons-up-down`, already in symbols). ONLY Group By uses the pane-flip disclosure (clicking it swaps the content below for the option list, the Swift-pane pattern); Order, Date By, and Sub-Group are dropdown pickers.
- **B-2:** [confirmed] Group By options: Location (structural) + the schema's groupable properties — select, status, date/datetime. Checkbox is OUT of grouping (pipeline supports it; the pane never offers it).
- **B-3:** [confirmed] Table default = Location (structural) — matches today's default group config.
- **B-4:** [confirmed] No "None" Group By option now — the `flat` kind stays reserved. "None" arrives with the flattened mode as a Prospect (→ Handoff Pending Focuses).

#### C — Location Grouping
- **C-1:** [confirmed] Order for location: `Custom` (default ALWAYS — view-owned `group_order`, today's behavior) or `Location` (mirror filesystem order). In Location mode, drag-to-order on BOTH surfaces (pane hierarchy + table bands) WRITES the filesystem (moveSet/reorderChildren), and fs order reads back so sidebar/table/pane agree.
- **C-1a:** [confirmed] The Location-mode gate is explicit new logic: the pipeline SKIPS `orderGroups` when `order_mode = 'location'` (today it applies `group_order` unconditionally — bandOrder.ts has no mode awareness). The stored `group_order` is PRESERVED, not cleared — ignored while in Location mode, restored on the flip back to Custom (the FK-survival rule).
- **C-1b:** [confirmed] Location-mode drags route through the same fire-time-merge commit discipline the reparent path already uses (TableView's commitBandRef), so an fs-order write can't race a mid-flight view persist — they're two writers on different files but one refetch loop.
- **C-1c:** [confirmed] The gate has TWO edit sites, not one: alongside the pipeline skip (C-1a), the band-drop ROUTER branches on `order_mode` — under Location, a SAME-PARENT reorder routes to `reorderChildren` (fs write) and does not write `group_order`; in Custom it writes `group_order` as today. The gate scopes to the same-parent reorder path ONLY: a cross-tree reparent ALWAYS writes `group_order` after its `moveSet` (slot preservation per C-1a — without it, flipping back to Custom would surface the band at a stale slot), independent of mode. Without the reorder branch the Location-mode drag writes an ignored order and silently no-ops.
- **C-2:** [confirmed] The pane body shows the set hierarchy — sets w/ sub-sets as disclosures, no individual pages.
- **C-3:** [confirmed] No "None" group row (diverges from Figma) — replaced by an `Ungrouped: Top/Bottom` footing toggle in footing typography.
- **C-4:** [confirmed] Sub-Group row appears only when Group By = Location. Defaults to Location (= today's nested structural). Can be a groupable property instead: sets stay top-level bands, property buckets render inside each set, and sub-sets FLATTEN (their pages roll up). When the schema exposes no groupable property, the picker offers Location only.
- **C-7:** [confirmed] Sub-Group carries its own subordinate `Order:` row (the Sub-Order) directly beneath it — same order options as a top-level group of that kind.
- **C-8:** [confirmed] Row hierarchy + typography: `Group By:`, `Sub-Group:`, and `Date By:` rows are peers — label-primary at Body. Each `Order:` row beneath its parent is subordinate — label-secondary at Control-Emphasized, with the padding to its parent row slightly reduced so the pair reads grouped. Trailing values everywhere keep the menus' existing detail treatment (Footnote/Emphasized in the side cluster's secondary tone).
- **C-9:** [confirmed] Footing rows (`Ungrouped:`, `Separation:`, `Hide Empty Groups`) are label + current value + double-chevron in footing typography; clicking pops a NATIVE context menu with the options. Hide Empty Groups surfaces the existing `hide_empty_groups` config (pipeline already honors it) — Swift-pane precedent carried forward.
- **C-10:** [confirmed] Loose root-level pages under Sub-Group = property: one flat ungrouped tail (no bucketing — there's no set band to bucket inside), at the loose-inset like today's ungrouped rows, bottom by default, placed by the Ungrouped toggle.
- **C-5:** [confirmed] Figma's `Flatten` AND `Hide Location` toggles are both Prospects — Hide Location belongs to the flattened mode (governs the location subtitle in title cells). Neither builds now.
- **C-11:** [assumed] When Sub-Group is a date property, a `Date By:` row appears beneath Sub-Group (above its Order row), same logic as the top-level one.

#### D — Property Grouping
- **D-1:** [confirmed] Orders for select/status: Default / Reversed / Custom — mapping to the existing `order_mode` = configured / reversed / manual.
- **D-2:** [confirmed] Custom flattens the pane list into one "Options" chip list for manual drag-reorder; writes `group.order`, never the schema. Drag disabled in Default/Reversed.
- **D-3:** [confirmed] Default = schema option order w/ status grouped by its groups; Reversed reverses the groupings too.
- **D-4:** [confirmed] Group headings in the TABLE: select/status use their actual glyphs (chips); status always renders pill regardless of the column's style. Date&time headings show the property's icon + set-header typography. (GroupHeader already does all of this — spec ratifies it.)
- **D-5:** [confirmed] The "+" hover on group headers is disabled when grouped by anything other than location (can't infer a create location from a property bucket) → TableView.md Prospects entry for the future fix.
- **D-6:** [confirmed] Date grouping: Order = Ascending / Descending (no Custom). A `Date By:` picker row appears under Group By when a date property is chosen — Day / Week / Month / Year, defaulting to Month. The pane pre-selects Month on an unset config — the same value the pipeline falls back to — so the displayed selection and the rendered buckets never disagree.
- **D-8:** [confirmed] Date group headings in the table follow the view's applied date format for that column — a written format renders "July 2026"-style buckets; a numeric format renders "07-2026"-style. Under a numeric format, a `Separation: Dash/Slash` footing toggle appears governing the heading's separator.
- **D-9:** [confirmed] The chip list under property grouping in Default/Reversed is a read-only preview — no interactions; drag only exists in Custom.
- **D-10:** [confirmed] Order labels, ratified (supersede Swift's wording): Select & Status = Default / Reversed / Custom; Date = Ascending / Descending; Location = Custom / Location. Nathan: Default/Reversed reads easier for select than Swift's labels.
- **D-11:** [confirmed] Every group band in the table is collapsible exactly like structural folders today — property buckets and sub-group buckets included.
- **D-11a:** [confirmed] Collapse keys get scoped, backward-compatibly: existing bands keep their bare keys (set ULIDs, property values, the top-level `_ungrouped`) — no migration; the NEW band kinds sub-grouping introduces take composite keys (sub-group bucket = set+bucket, per-band no-value region = set+ungrouped) so one set's collapse never bleeds into its twin in another set or into the top tail. Today's `collapsed_groups` is one flat namespace-less set — the composite scheme is what keeps the new regions distinguishable.
- **D-7:** [confirmed] The Ungrouped Top/Bottom footing toggle is ONE global knob: it places the top-level ungrouped tail (location + property grouping's value-less rows) AND, when sub-grouped by a property, the no-value pages *within each set band*. One toggle, every ungrouped region. This is NEW branching at every tail emit site — the pipeline currently hardcodes pinned-last at all three (property/structural/flat; four with sub-grouping) and never reads a placement value.

#### E — Model & Persistence
- **E-1:** [confirmed] `GroupConfig`'s structural variant extends in place: `{ kind: 'structural', order_mode?: 'location' | 'custom', sub_group?: { property_id, order_mode, order?, date_granularity? } }`. Absent fields decode to defaults (custom + location sub-group = today's behavior). Rejected alternatives → Considered & Rejected.
- **E-2:** [confirmed] The Ungrouped toggle persists as a view-level field, default Bottom (one global knob per view — survives Group By switches); the property config's `empty_placement` stays as decode parity. Separation (dash/slash) persists as a small per-view display field.
- **E-3:** [confirmed] A deleted/unmappable grouped property falls back to structural (pipeline already does); the pane displays Location in that state. A stored `sub_group` survives Group By switches as a preserved foreign key — flip back to Location and it's still there. `order_mode` follows the same survival rule (preserved across switches), and it's meaningful — and reachable in the pane — ONLY under location grouping; property grouping never offers it.
- **E-4:** [confirmed] Framing correction from review: the sub-group resolution is NET-NEW pipeline logic — a second resolver stage (flatten sub-sets per set band, re-bucket by property) that exists nowhere in group.ts. The decoder change (E-1) is the trivial part; the resolver stage is the build. The stage owns THREE obligations the existing stages carry individually: (1) it slots into the resolveView chain after structural resolution (a named position, like orderGroups); (2) it applies the global sub-bucket order (`sub_group.order` via the bucketOrder machinery) — no existing stage reads it; (3) it re-applies the view sorter to each sub-bucket's items (parity with every other band — sorting is per-group, never global).

#### F — Table Interactions Under Sub-Group
- **F-1:** [confirmed] Sub-group bucket bands are draggable ONLY when Sub-Order = Custom. Dragging a bucket heading under any one set reorders that bucket across ALL sets — the sub-order is global, never per-set — and writes `sub_group.order`.
- **F-2:** [confirmed] A row dropped into a different set's bucket writes BOTH — `movePage` into that set + `setProperty` for the bucket's value (the existing cross-group reassignment, extended across the set dimension).
- **F-3:** [confirmed] The pane's hierarchy list while sub-grouped by a property shows a FLAT set list (sub-sets are flattened away); buckets aren't repeated per-set.
- **F-4:** [confirmed] Pane hierarchy drag rules mirror the table band rules — sibling reorder writes view order in Custom / fs in Location; a cross-nesting drop is always an fs reparent.

#### G — Pane Mechanics
- **G-1:** [confirmed] The Group By pane-swap is a VERTICAL disclosure, not a PaneSlider push — the Swift precedent (GroupingPane.swift's inline-expand picker): clicking the row discloses the option list below it in place of the body, the pane's height animating open/closed like a dropdown; selection state marks the active option; picking (or clicking the row again) un-discloses back. React vehicle: the body region conditionally renders the option list OR the hierarchy/preview inside the shared `Reveal` disclosure motion — a single Reveal only grows/collapses one subtree, so the swap is a conditional render riding the disclosure, not one Reveal "swapping" two bodies. (PaneSlider tolerates this: its slot height is untransitioned between nav flips precisely so in-place child disclosure tracks live.)
- **G-2:** [confirmed] The middle region (the list between the dividers — location hierarchy or option chips) is its own scrollable body wearing the shared `OverflowScroll` vertical fade (`overflow-eclipse-y`, the DRY'd scroll-edge blur the Icon Picker wears); value rows above and footings below stay pinned (MenuScrollFrame's pinned header/footer shape).
- **G-3:** [confirmed] Date group headings resolve through the existing `formatDate()` + the view's `column_styles` for that property — GroupHeader's datetime branch stops rendering the raw bucket key.
- **G-4:** [confirmed] Footing native menus ride a small dedicated value-pick IPC in the family of the existing `context-menu` handler (Menu.buildFromTemplate + popup); picks write through the standard `views:save` path.
- **G-5:** [assumed] Boolean footings (`Hide Empty Groups`) render as Figma's checkbox-style toggle (click flips); only the value footings (`Ungrouped:`, `Separation:`) pop the native menu.
- **G-6:** [assumed] The Hide Empty Groups footing appears only under property grouping (the Swift-footer precedent; `hide_empty_groups` lives on the property config) — location grouping keeps showing empty sets.

#### H — Reconciliation (docs/code that go stale on ship)
- **H-1:** [confirmed] `Views.md` — "Group … open blank leafs" and the Pending "View-Settings Editing Panes" entry become false for Group; the pipeline's Group paragraph gains sub-grouping, the location order mode, and the global ungrouped placement.
- **H-2:** [confirmed] `TableView.md` — the Groups section gains sub-group bands + collapse keys + the fs-writing drag mode; the ungrouped-tail description gains the Top placement; Prospects gains the disabled off-location "+" entry; the band-drag paragraph's "only a cross-tree drop touches the filesystem" becomes conditional on Order = Custom.
- **H-3:** [confirmed] Handoff Pending Focuses gains the "None"/flattened-mode prospect at close-out; History.md logs the locked decisions at ship.
- **H-4:** [confirmed] `decodeGroupConfig`'s structural branch currently drops extra fields — E-1's new fields must survive decode (the lenient decoder grows, no migration needed).

### Core (must-have)
- The Grouping leaf behind both doors (SettingsPane + ViewSettings), replacing the blank leaf: Group By (pane-swap disclosure) · Order (dropdown) · Date By (date properties) · Sub-Group + Sub-Order (location only).
- The middle region: location hierarchy (draggable per mode) / property preview (read-only in Default/Reversed) / flattened Custom chip list (draggable, writes `group.order`).
- Footings: Ungrouped Top/Bottom (global, first reader of the placement semantics) · Separation Dash/Slash (numeric date formats) · Hide Empty Groups — all native-menu value picks.
- Pipeline (all three are NET-NEW logic, not config surfacing): the sub-group resolver stage (sets → property buckets, sub-sets flattened, global bucket order); Top/Bottom placement branching at every ungrouped-tail emit site; the Location-order gate (skip `orderGroups`, preserve-but-ignore `group_order`).
- Table: sub-group bucket bands (headers, composite collapse keys per D-11a, Custom-only global drag); fs-writing band/pane drags under Order = Location riding the existing fire-time-merge commit discipline; date headings following the column's date format; "+" disabled off-location.
- Model: E-1 GroupConfig extension + view-level placement/separation fields, lenient decode to today's defaults.

#### Prospects (allowed later, not now)
- **Flatten + Hide Location** — the flattened mode (groups flatten; location renders as a subtitle in title cells, Hide Location governing it); Figma shows both toggles — don't build. Don't-foreclose: the footing region takes new rows without layout change.
- **"None" / flat grouping** — arrives with the flattened mode; the `flat` GroupConfig kind stays reserved (→ Handoff Pending Focuses).
- **Group-header "+" under property grouping** — needs page-preview/creation surfaces; until then the "+" disables (→ also to TableView.md Prospects).

#### Out of Scope (won't do)
- Grouping panes for the other view types (calendar/gallery/timeline/cards/list) — mechanically different; separate specs.

#### Considered & Rejected
- **Group levels array** (generalize `group` into a recursive list of group keys, collapsing Group By/Sub-Group into one mechanism) — elegant but rewrites the decoder + pipeline contract for a depth-3 hypothetical nobody asked for, and breaks the Swift-versioned shape. Over-engineering.
- **View-level `sub_group` sibling field** (leave GroupConfig untouched) — splits one concept across two homes; the structural variant owning its own sub-group is the honest shape.
- **Per-set sub-order** — rejected outright: bucket order is global across sets; per-set order would fragment the mental model and the write path.

#### Lessons
- The on-disk model was already ahead of the UI (`order_mode`, `empty_placement`, `hide_empty_groups` sitting unread or decode-parity) — ground in the schema before inventing config shapes; the pane mostly SURFACES existing plumbing.
