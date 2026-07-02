## Tables Next-Parts (Cells + Group Drag + Styles) — Decision Log

> Status: **RATIFIED (Nathan, 07-01)** → `writing-plans`, three plans (one per Core phase), Phase 1 first.
> **Standing constraint (Nathan, at ratify): ZERO regression to the shipped table styling** — the coupled elastic-title mechanism (`minmax` title + reflow-floored grid `min-width` + heading both-side padding), the full-bleed heading band, the between-rows collapse-aware divider model, sticky group headers, and the col-drag `zoom` compensation are hard-won (`Features/TableView.md`); every plan carries this as a Global Constraint and every phase ends with a visual verification pass (CDP screenshots against the live app) before closeout.
> **CONVERGED — review-certified.** Two adversarial rounds ran: round 1 (3 blockers + 14 findings, all folded — the structural-order schema extension, the moveSet order-leak guard, the drag-arm regression guard, the (×) context table) and round 2 (verified the folds; both hard targets held — the flat set-id array orders siblings per level, the order-leak guard reads from the tree's resolved `source.sets`; 3 one-line doc fixes, applied). Supersedes the raw prep doc's §2 as the working artifact. On ratify → `writing-plans`, three plans (one per Core phase). Decisions tagged `[confirmed] / [assumed]`.

### Frame

- **Purpose:** Design the table view's interactive layer — in-line cell editing + rendering (per-type gestures), Set/group dragging inside the table, heading-row Style menus, the hover "+", and the chip slide mechanic — as one coherent interaction model over the shipped pipeline + PropertiesV2 data layer.
- **Core Value:** A table whose cells are directly manipulable — every property type readable, editable, and styleable in place — with structural drag (Sets) matching the sidebar's semantics.
- **Success Criteria:** Every gesture in the per-type matrix below works as specced; a Set band drags to reorder/reparent with sidebar-identical rules; heading Style choices persist and re-render; no "on every X" perf regressions (the PommoraDND measurement discipline holds).

### Sources

- `Detail/Views/Table/TableView.tsx` · `Cell.tsx` · `tableDnd.tsx` · `Table.css` — the render + drag paths (explorer grounding in flight).
- `main/columnMenu.ts` · `main/tableMenu.ts` — the native menus (Align + Hide exist).
- `Sidebar/sidebarDnd.tsx` + `sidebarDndModel.ts` — set-drag prior art (cycle guard, reparent rules, `moveSet`); just perf-fixed (snapshot discipline).
- [[PommoraDND]] — the measurement discipline (root-caused 07-01): geometry at activation, never per move.
- [[TableView]] · [[Interaction]] — renderer spec + the motion law (Bloom is THE pane-open primitive).
- PropertiesV2 (SHIPPED 07-01; spec pruned) — defs nexus-wide; option edits cascade to every assigner; Plan 2 (assign surface) folds into View Settings. Durable record: `History.md` (07-01 entry) + `Features/Properties.md`.
- `design-system/components/PickerMenu` — the notch picker, built and unconsumed; the intended in-line edit surface.
- `design-system/tokens/typography.css.ts` `truncateHoverScroll` + `chip.css.ts` `chipLabel` + the sidebar scroll-fade/`slideTitleBack` — the chip slide mechanic's pieces.

### Decisions

#### A — Per-Type Cell Gestures (Nathan's directives, 07-01)

> **Portability (Nathan):** this matrix is the interaction contract for **every property-rendering surface, not just the table** — the Gallery (and Board/List/Cards, v0.5.0) inherit it: value = single-click, meta = right-click, open = the title element, chips carry the slide + (×) everywhere. Design the cell editors as surface-agnostic pieces (the type-aware editor + PickerMenu anchor to any element), so Gallery cards consume them rather than re-deriving gestures.

> **Correction (Nathan, 07-01): every "double-click" in the gesture directives means RIGHT-CLICK.** Rewritten below; the click-disambiguation problem this dissolves is recorded in Considered & Rejected.

- **A-1:** [confirmed] **Title cell:** single-click → enter the page; right-click → context menu (Rename, Change Icon, Delete); hold → drag. **Guard (review round 1): ALL cells keep arming row-drag past the `ACTIVATION` threshold** (the shipped whole-row arming, commit a8c18ef) — cell editors own only the sub-threshold press-release; the matrix must not regress any-cell arming to title-only.
- **A-2:** [confirmed] **Status cell:** single-click → the options dropdown (checkbox style: the three-state cycle, A-6); right-click → **Style ONLY** (Pill/Capsule/Checkbox — no option management, no colors; those live in the Properties pane per B-7) — **uniform across every status style**. The full status division of labor: **value = click · style = right-click (cell or heading) · option content = Properties pane.**
- **A-3:** [confirmed] **Link cell:** single-click → opens the link; right-click → a **context menu: Style > (Title, Full Link) · Edit** — Edit enters the in-line editor; never straight into editing from the click.
- **A-4:** [confirmed] **Select / Multi-select:** single-click → picker (the chip picker).
- **A-5:** [confirmed] **Date & Time:** single-click → opens the picker. The picker is a **calendar component — Swift's DateTimePicker is the visual reference — scoped as its own pass AFTERWARDS**; until it lands the datetime cell stays read-only.
- **A-6:** [confirmed] Checkbox-style status single-click **CYCLES the three GROUPS, never the options within them**: empty (Upcoming) → `minus` (In-Progress) → `check` (Done) → empty — each step writing that group's **first-in-order option's value** (a group with zero options is skipped in the cycle — possible once the pane's option editing lands). Picking a *specific* option within a group is a pill/capsule-style affair — the checkbox style trades that precision for the one-click cycle by design.
- **A-7:** [confirmed] **Row-click narrows to the title cell.** "Click anywhere to open" dies; open is the title's gesture, every other cell's single-click belongs to its own editor.
- **A-8:** [confirmed] **Number cell:** single-click → in-line numeric editing; right-click → **Style** → the existing number styles (currency, decimals, …) — ground the exact set from Swift's number-format options at planning, like `date_format`.
- **A-9:** [confirmed] **File cells work just like links:** right-click → a **context menu: Style > (filename / full path) · Edit**. Files render as **per-file chips, each click-target scoped to its own text box** — clicking a chip opens THAT file (replaces today's joined-string render); the chip-native (×) removes per-file.
- **A-13:** [confirmed] **The remaining matrix rows:** **select/multi right-click → Style >** (the chip-style set — exact contents grounded at planning) · **checkbox property** — click toggles, right-click → Style (Checkbox/Switch) · **datetime right-click** — Style → Options, mirroring its heading. Right-click = a Style menu on every value cell, no exceptions.
- **A-14:** [open→parked] **Context-tier cells** — tier relations are frontmatter, not registry props; their in-cell editor (a context picker?) is its own small design → Prospects. Until then they stay read-only chips.
- **A-10:** [confirmed] **No text property type exists** — no text-cell editing to design.
- **A-12:** [confirmed] **The universal in-line edit commit model** (link, file, number — every cell editor): **Enter = confirm · click-out = save · Esc = revert and exit.** Link/file values validate through `shared/links` on commit.
- **A-11:** [confirmed] **Link "Title" style shows the FETCHED page title by default** (fallback: the URL when no title is available). [assumed] Fetching implies a fetch+cache design — when the title is fetched (on value write), where it's cached (never blocking the render path), offline fallback — a planning-level mechanism, logged here as the requirement.

#### B — Heading-Row Menus

- **B-1:** [confirmed] Heading context menu structure: **Align >** · **Style >** · **Hide** (Align + Hide already ship in `columnMenu.ts`; Style is net-new).
- **B-2:** [confirmed] Per-type Style submenus: **Date & Time → Options** (Swift's `date_format` set) · **Status → Pill, Capsule, Checkbox** · **Checkbox → Checkbox, Switch** · **Link → Title, Full Link** · **Number → the existing number styles** (currency, decimals, … — Swift's set) · **File → the link analog** (filename / full path) · **Select/Multi → the chip-style set** (mirrors the cell menu per A-13 — cell/heading parity holds for every styled type).
- **B-3:** [confirmed] **Style persists per-VIEW on `SavedView`** (a `column_styles` sibling of `column_alignments`) — two views of one Collection can render Status differently; no nexus-wide cascade from a right-click. Consequence: the def-level style/format riders (`display_as`, and per review round 1 the same-shaped `date_format`/`number_format`/`time_format`) are **orphaned by this decision** — none was ever a modeled zod field, so "removal" = drop them from the fixtures + the rider comment; on-disk copies stay inert foreign keys by the ride-through design. Chosen formats persist in `column_styles`, one channel only.
- **B-4:** [confirmed] Date & Time's Style → **Options** = the format choices **pulled from Swift's `date_format` option set** — grounding the exact Swift enum happens at planning time. **The format plumbing is net-new (review round 1):** `formatDate` is a hardcoded `toLocaleDateString` today, `date_format` has zero read sites — Core ships the format wiring into `Cell.tsx`, reading from `column_styles` (per B-3, not the def).
- **B-5:** [assumed] The Style submenu extends the existing native `columnMenu.ts` (Align/Hide live there; `ColumnMenuContext` grows a `style` field + per-type items). Same IPC → persist pattern as `column_alignments`.
- **B-6:** [confirmed] **Checkbox-style status uses the Lucide `minus` glyph:** empty = To-do group, `minus` = In-Progress group, `check` = Done group — the three glyph states single-click cycles through (A-6).
- **B-7:** [confirmed] **Status option COLOR is pickable via a menu in the Properties pane** — a per-option color menu in the pane's per-property editor (the "options — pending" area). Under PropertiesV2 this is a **global def edit** (`editProperty` on the registry — every assigning Collection sees it). **This entry is the requirement's ONLY record** (the prep doc that co-held it was pruned) — the future View-Settings/assign-surface brainstorm inherits it from here + the Handoff's Axis 2.

**Grounded facts (cell/menu explorer, 07-01):**
- **No row context menu exists at all** in the container table (right-click on a row = nothing; `tableMenu.ts` is the MarkdownPM widget's, a false lead). Title's double-click menu is net-new — the native-menu pattern (`columnMenu.ts`) is the template.
- **`PickerMenu` (the notch picker) is fully built with ZERO consumers** — the obvious shell for the status/select cell dropdown, but unproven in the app.
- **No date picker exists in React** (Swift's is unported). Datetime cells are inert text today.
- **Per-option editing (select/status labels/colors) is explicitly unbuilt** (`PropertiesPane.tsx:96` "options — pending") — cell pickers can only pick existing options until that lands (in-cell option-create is gated on it + cascades globally per PropertiesV2).
- **Chip slide pieces:** `truncateHoverScroll` is pure CSS (native scroll + mask fade via `--scroll-fade`); the sidebar adds two JS pieces — a capture-phase scroll listener toggling `.title-scrolled` (React 19 doesn't delegate scroll) and the `slideTitleBack` rAF tween (scrollLeft isn't CSS-transitionable). The DRY primitive = extract (b)+(c) from Sidebar into a shared hook; table chips currently have neither.

#### C — Set / Group Dragging (table view)

- **C-1:** [confirmed] Entire Sets drag within their Collection in the table view — reorder among siblings, **sub-set nesting reorder**, and **moving across Sets** (reparent). Sidebar `moveSet` semantics are the prior art (cycle guard, order arrays).
- **C-2:** [assumed] The drag follows the PommoraDND measurement discipline (snapshot at activation) — non-negotiable per the root-cause capture. (Both `tableDnd` and `sidebarDnd` now do this — house standard.)
- **C-3:** [confirmed] **All band kinds drag, and vertical band reorder is ALWAYS per-view** — **never the filesystem, even for structural-set bands** (Nathan: "re-ordering a grouping band doesn't change the filesystem, even when it's grouped via filesystem"). The sidebar's `set_order` and the table's band order are independent orders. **Schema reality (review round 1):** `order`/`order_mode` exist only on the *property* group variant; the structural variant is a bare `{ kind: 'structural' }` whose band order derives from fs `set_order` — so this decision requires a **net-new schema extension**: the structural group config gains the same manual-order shape (a flat set-id array — ids are unique across nesting levels, so one array covers the tree), first write flips it manual, read path prefers it over the fs order. Property bands write the existing `group.order` (its first UI writer).
- **C-4:** [confirmed] **Reparent = filesystem, order = view.** Dragging a Set band INTO another Set (nesting / moving across Sets) commits `moveSet` (folder move — membership is filesystem-derived); the vertical band order stays the view's order in every case. **The order-leak guard (review round 1):** `moveSet` mandatorily rewrites the destination's fs `set_order` — the reparent commit passes the destination's *current* fs order + the moved id **appended**, never the visual drop position; the drop position persists only in the view's band order. Otherwise the per-view order silently leaks into the filesystem.
- **C-5:** [confirmed] Band-drag details: the **ungrouped/root band never drags** (structurally pinned last); a Set band **walks its FULL tree** (Nathan) — de-nest to Collection root, nest into any non-descendant Set, any depth; Esc-abort for drags is **net-new** (tableDnd/sidebarDnd handle `pointercancel` only) and ships with the band-drag work for all drag surfaces.
- **C-6:** [confirmed] **No drag handles on group headers — the GLYPH (the Set icon + name span) is the drag surface** (Nathan, 07-01): hold-drag on the glyph arms the band drag; the twisty + "+" keep their own clicks (stopPropagation).

**Grounded constraints (explorer, 07-01 — the design must respect):**
- **Group headers are structurally outside the drag surface today** — zero pointer wiring, excluded from `dataRows`/`TableRowDnd` by design (`TableView.tsx:507-509`). Set-band drag is a genuinely new gesture surface, not a row-drag variant.
- **Reorder and reparent are ONE commit** — `moveSet { path, newParentPath, order }` always rewrites the destination's `set_order`; same-parent reorder = `moveSet` with `newParentPath` unchanged. Don't invent a reorder-only op.
- **The sidebar's pure model is directly reusable** — `isSelfOrDescendant` (cycle guard), `slotInGroup`, `nextOrder` are container-agnostic pure functions.
- **The table is single-container** — a Set can only land inside the open Collection's own subtree, so the sidebar's "never on a context/top level" rule is unreachable here; cross-Collection drag-out is inherently out of table scope.
- **`ResolvedGroup` carries only `key` (the Set id), no `path`** — a commit needs an id→path map built the `buildSetNames`/`buildSetIcons` way from `source.sets`.
- **Nesting is recursive `ResolvedGroup.children`** — hit-testing must know which sibling `set_order` array a header hover implies (walk the recursion or flatten an id→parent map).
- **Collapse state is per-view on-disk** (`SavedView.collapsed_groups`), keyed identically to band keys — dragging a collapsed band needs no new identity scheme.
- **The PommoraDND engine (`SortableZone`/`DragGroup`) is NOT the vehicle** — it models displacement/reflow; the table + sidebar both chose the no-displacement insertion-line gesture. Extend the bespoke line-gesture pattern.
- **`canReorderWithin = sortKeys < 2`** — the existing row-reorder lock (multi-key sort kills manual order). Set bands are structural, so band-drag likely stays legal regardless of row sort — but that interaction (sorted rows inside dragged bands) needs a decision.

#### D — The Hover "+"

- **D-1:** [confirmed] The "+" that reveals on hover gets properly wired up (today it's a deliberate inert placeholder — no `onClick`, `cursor: default`).
- **D-2:** [confirmed] Semantics: creates a new page **in that Set** (Set bands) / **with that group's property value pre-filled** (property bands). **Placement is hardcoded bottom-of-group for now** — the review found `newItemsTo` doesn't exist on `SavedView` (a comment invented it); the knob itself is the Layout pane's job (the sibling View-Settings scope adds the field later).
- **D-3:** [confirmed] Root/ungrouped band "+" = plain create at the Collection root; **date-bucket bands HIDE the "+"** (a bucket key isn't a writable value).

#### F — Menu / Picker Architecture

- **F-1:** [confirmed] **Split by job:** *native Electron menus* for the meta layer — the title context menu (Rename/Change Icon/Delete), the heading Align/Style/Hide, the status style options — extending the proven `columnMenu.ts` pattern. *In-DOM `PickerMenu`* (the notch picker, its first real consumers) for the **value** dropdowns — status options, select/multi chip pickers, the capsule-look precision list — because option chips can't render in a native menu.
- **F-2:** [assumed] PickerMenu anchors with its notch at the cell (its `--dropdown-origin` bloom), closes on outside-click/Esc via the existing `useDismiss`/`useExitPresence` conventions; a value pick commits through the `setProperty` mutate op (the existing single-value write path — no new IPC).

#### E — Chip Mechanics (slide + remove)

- **E-1:** [confirmed] DRY the sidebar's scroll-fade eclipse + spring-back-on-leave onto chips (which already share `truncateHoverScroll`) — one shared overflow mechanism, sidebar + chips (+ eventually table cells). Grounded: the base is pure CSS; the two JS pieces to extract from Sidebar are the capture-phase scrolled-flag listener and the `slideTitleBack` rAF tween.
- **E-2:** [confirmed] **Chip-native value removal:** on hover of any chip, a **tinted floating (×) that blurs on the right side of the chip** — removing that value from the entity. DRY'd into the chip components **themselves**, not per-surface.
- **E-3:** [assumed] The (×) is opt-in per context (an `onRemove` presence-prop). **The context table (review round 1 forced enumeration):** multi-select chip = remove that value · single-select chip = clear the value · status chip = clear the value (row moves to the no-value band) · context chip = remove that tier relation · **file chip = remove that file from the value (A-9)** · picker's selected chips = deselect · presentational chips (group-header glyphs, read-only surfaces) = no (×). The (×) click **stops propagation** (it must not also open the cell's picker). Geometry: the slide fade is the LEFT edge, the (×) floats RIGHT — compatible by construction.
- **E-4:** [confirmed] Perf constraint: the slide/(×) mechanics stay CSS-first; the scrolled-flag listener is ONE capture-phase listener per container (the sidebar's shape), never per chip — the "on every X" rule applied to listener counts.

### Don't-Forget Sweep (interactive + structural — run 07-01)

- **Every action's inverse:** picker open → `useDismiss`/Esc close (F-2) · chip (×) remove → re-add via the picker (E-2/E-3) · checkbox cycle → keeps cycling (A-6) · style change → the menu's radio (B-1) · band drag → Esc/pointercancel abort (tableDnd pattern) · in-line edit → the A-12 model (Enter confirm / click-out save / Esc revert) · column Hide → **un-hide lives in the Visibility pane (the View-Settings brainstorm's scope)** — until that pane ships, Hide's only inverse is editing the sidecar; acceptable, already true today.
- **Revealed controls stay reachable:** the (×) rides the chip's own hover (clicking it is inside the hover zone ✓); the "+" already has the group-header-hover reveal pattern ✓.
- **Local vs global gestures:** click-vs-drag on the same cell disambiguates by the existing `ACTIVATION` threshold (tableDnd) ✓; cell right-click menus replace the (unhandled) default row context menu — no collision ✓; PickerMenu must not swallow ⌘Z / page scroll (dismiss-on-scroll or scroll-within only — planning detail).
- **Validation:** link edits validate via `shared/links`; a value pick can only pick existing options (per-option editing is unbuilt — grounded).
- **Persistence:** `column_styles` is an additive `SavedView` field (looseObject — absent = per-type default, no migration; rides as a foreign key for any other reader) ✓; `group.order` uses the existing schema, first UI writer ✓; `display_as` removal touches only fixtures + the def schema (zero readers, grounded) ✓.
- **Failure recovery:** drag commits stay commit-on-drop through the store's `mutate` (a failed `moveSet` returns the envelope error and the tree refetch restores truth — no optimistic fs state) ✓; value picks ride the existing `setProperty` path ✓.
- **Concurrency:** band drag during a watcher tree-swap → the snapshot-dirty discipline (C-2) ✓.
- **Performance:** the chip slide/(×) mechanics stay CSS-first; the scrolled-flag listener is ONE capture-phase listener per container (the sidebar's shape), **never a listener per chip** — hard constraint, logged as E-4.
- ~~Number / text / file cells~~ → resolved: number = A-8, file = A-9, text properties don't exist (A-10).

### Core (must-have) — three phases (review round 1: these share almost no code paths; one mega-plan invites a mega-diff)

**Phase 1 — Cells, menus, styles (A/B/F):** the per-type gesture matrix (title enter/menu/drag, status pick + group-cycle, select/multi pickers, link/file open + Style/Edit menus, per-file chips, number edit + Style, row-click narrowed to title, the A-12 edit model); the menu split (native meta menus extending `columnMenu.ts` + PickerMenu value dropdowns — its first consumers); per-view `column_styles` + wiring every style into `Cell.tsx`'s switch (formats included — net-new plumbing per B-4). **Link Style > Title WORKS from day one** (Nathan): Title displays the fetched title once the fetch Prospect lands, falling back to the URL until then; **both Title and Full Link render in the linked color** — link cells adopt the link color token.

**Phase 2 — Band drag (C):** the new header-drag gesture surface (insertion line, snapshot discipline, cycle guard, id→path map), the structural-order schema extension (C-3), the order-leak-guarded `moveSet` reparent (C-4), Esc-abort (C-5, retrofit to all drag surfaces).

**Phase 3 — Chip mechanics (E):** the DRY'd slide (shared hook: one capture listener per container + the rAF spring-back) + the native hover (×) with the E-3 context table, in the chip components; the "+" wiring (D — small enough to ride with either phase).

#### Prospects (allowed later, not now)

- **The calendar date picker** — Swift's DateTimePicker as the visual reference; its own pass (Nathan). Until then datetime cells are read-only; their Style→Options (format) menu still ships with Core because Core builds the net-new format wiring (B-4 — `formatDate` is hardcoded today). *Don't-foreclose:* A-5 reserves the single-click gesture.
- **In-cell option-create** (type-to-create in the picker) — gated on the per-option editing pane (unbuilt) + it edits the global registry def (PropertiesV2 cascade); needs its own confirm/UX pass.
- **The link-title fetch mechanism** (A-11) — the fetch+cache design (when fetched, where cached, offline fallback); the Style>Title knob works from day one with URL fallback, so this upgrades the display in place.
- **Context-tier cell editing** (A-14) — the context picker for tier chips; frontmatter relations, its own small design.
- **Keyboard navigation across cells** (arrow/tab/Enter matrix) — the prep doc's open question; not in the gesture directives; layers on later without rework.

#### Out of Scope (won't do — distinct from Prospects)

- The View-Settings panes + the PropertiesV2 assign surface — the sibling brainstorm's scope (`7-1 - View Settings + In-Cell Editing + ViewPane — Brainstorm Prep.md` §1).
- Cross-Collection Set drag-out of the table — the table renders one container; that's the sidebar's job.
- Changing the drag interaction language (adopting the reflow/displacement engine) — the insertion-line gesture is the chosen product behavior.

#### Considered & Rejected

- **Double-click as the meta gesture** — dissolved: Nathan's directives meant right-click; kills the click-window disambiguation problem outright.
- **Per-def style persistence** (`display_as`) — a right-click restyling every assigning Collection nexus-wide is too big a blast radius; per-view chosen; the dead field is removed.
- **All-DOM menus** — re-invents what native menus already do for meta actions; split-by-job chosen.
- **"Click cycles the value" for status/select** — rejected as the general model (fights discoverability + the specced dropdowns); survives only as the checkbox-status three-state cycle (A-6).
- **The checkbox-status right-click capsule dropdown** — briefly adopted as the precision hatch, then **voided** once the three-state cycle landed (the cycle covers group-level picking; right-click returns to the uniform Style menu).
- **Adopting `SortableZone`/`DragGroup` for band drag** — the engine models displacement/reflow, the opposite of the chosen insertion-line gesture; bespoke extension wins.
- **Band reorder writing `set_order`** — Nathan: band order is a view concern even when grouped structurally; the sidebar's order and the table's band order stay independent.

#### Reconciliation Forecast (what becomes false if this ships)

- `Features/TableView.md` — gestures, menus, band-drag sections (targeted rewrite).
- `Features/Views.md` — `SavedView` gains `column_styles`; `group.order` gains its first writer.
- `Features/Properties.md` + `shared/properties.ts` fixtures — `display_as` removed.
- `Features/PommoraDND.md` — the band-drag surface joins the inventory (post-ship), inheriting the measurement discipline.
- `Features/Interaction.md` — PickerMenu graduates from unconsumed to the value-dropdown primitive.
- The prep doc's §2 (in-cell editing) is superseded by this log.

#### Lessons

- (accrues)
