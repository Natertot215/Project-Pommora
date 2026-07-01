## View Settings (Part 3) + In-Cell Editing + ViewPane — Brainstorm Prep

**Status:** PREP for a fresh brainstorm loop, not a ratified plan. Nathan called for a full `studio-brainstorm` → `writing-plans` redo of these three subsystems; that loop is a dialogue with an approval gate and can't be run solo. This doc grounds it — what's actually built, the verdict on the "file per cell-type" idea Nathan flagged, the extracted intent, and the open questions to settle with him — so the brainstorm is fast.

### Why the old Part-3 doc is stale

The `6-28 - Table Views Part 3 — View Settings` doc is a running STATUS log, not a forward plan. Its "Built" section describes surfaces already shipped and verified to exist (`SettingsDropdown`, `ViewPane`, `PaneSlider`, `PropertiesPane`, `MenuSurface`, the `Switch` primitive, `ViewSettingsScope`); its "Pending" section is a real remaining-panes checklist but reads as status, not design. It also predates shipped work (the grid rewrite, Part 2 UIX, the label restructure) and never treats in-cell editing or ViewPane integration as designed subsystems — which is the actual gap. Start from its INTENT, discard its specifics.

### Subsystem 1 — View Settings pane (Part 3)

**Intent:** the glass dropdown behind the toolbar Settings button that drives a Collection/Set's schema + saved-view config, pane by pane.

**Already built:** the shell (scope-routed `SettingsDropdown`, `ViewPane` root menu, `PaneSlider` slide+resize, shared `MenuSurface`), the Properties pane (add/rename/reorder/delete/changeType over the `schema:*` IPC), standard icons, the `Switch` primitive, the `--input-field` alias, the glass split (liquid `GlassSegment` vs frost `GlassPane`).

**The real remaining plan (what to brainstorm):** the **Grouping** pane (toggle + group-by picker + order-mode / date-granularity / empty-placement / hide-empty), the **Sort** pane (multi-key list with the `isSortable` filter), the **Filter** pane (rule builder + operator picker + AND/OR nesting), the **Layout** pane (Format picker · Hide Page Icons · Hide Borders · Table Size · Display-As toggle · new-items placement · Open-In), the **Visibility** pane (show/hide + order + the un-hide path for the right-click Hide), and **View management** (rename/duplicate/delete + the active-view switcher). All wire to the Part-1 seams (`SavedView`, the `schema` / `views` / `activeViews` IPC).

### Subsystem 2 — In-cell editing

**Intent:** edit a cell's typed value inline in the table (activate a cell → edit → commit), across every property type.

**Verdict on "a file for each cell-type based on what property it uses" — it doesn't make sense; Nathan's instinct is right.**
- The read path renders EVERY cell through ONE type-aware component, `Detail/Views/Table/Cell.tsx` — a single `switch (v.kind)` over the resolved value kind (title / select / status / multiSelect / checkbox / context / url / number / file / datetime), ~90 lines, with chips already extracted into reusable `Chip` / `ContextChip`.
- A file-per-property-type shards that clean single-switch seam, scatters the type logic, and multiplies files for no gain — the opposite of the established pattern (and of the codebase's DRY rule).
- For EDITING, per-type edit *affordances* are legitimate (a select needs a picker, a date a date field, a checkbox toggles) — but as small composable pieces (functions / tiny components) that a type-aware editor switches into, reusing the same value-kind union and the existing pickers (the chip picker, `IconPicker`), NOT separate files per property.
- **Lean:** extend `Cell` with an edit mode, or add a sibling `CellEditor` that mirrors its `switch` — one type-aware editor, not N files. Precedent: `MarkdownPM/Tables/CellEditor.tsx` is a single editor component (a different surface — the markdown-table widget — but the same "one editor, type-aware" shape).
- Fold in [[project-row-drag-from-title-area]]: in-cell editing must let row reorder ALSO arm by dragging the title cell, not only the gutter grip.

**Open questions for the brainstorm:** the activation gesture (click vs double-click vs Enter), the commit/cancel model, which types get rich editors vs inline text, keyboard navigation across cells, and how editing coexists with row-drag-from-title.

### Subsystem 3 — ViewPane full integration

**Intent (as I read it — needs Nathan's framing):** the `ViewPane` root + panes exist as UI; "full integration" is wiring every pane to the live schema/view state and the active-view switcher so that changing a setting actually re-resolves and re-renders the table (group/sort/filter/visibility round-tripping through `SavedView` + the view IPC, not just local pane state).

**Open question — the one I most need from Nathan:** what "full integration" means precisely to him — the end-to-end wiring of the existing panes, or a broader scope. This frames whether Subsystem 3 is a distinct plan or the "wire it up" tail of Subsystem 1.

### What the brainstorm needs from Nathan

The open questions above — especially the in-cell-editing interaction model and the exact scope of "ViewPane full integration." Once those are settled, this decomposes into (likely) two or three implementation plans: the remaining Settings panes, the in-cell editor, and the integration wiring.
