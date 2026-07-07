### Views

A view is a saved presentation of a [Collection's](Collections.md) (or a depth-1 Set's) Pages. It never modifies its source — filtering, grouping, and sorting are presentation only.

Every Collection or depth-1 Set carries an ordered list of saved views, and one pure pipeline drives every renderer. Six view types are modeled — **Table**, **Cards**, **List**, **Gallery**, **Calendar**, and **Timeline** — an extensible registry, so a new type slots in as an add-on.

### Features

#### II. Saved-View Model

Each container's sidecar holds an ordered `views[]`. A saved view records its `id` (a ULID), `name`, `icon`, renderer `type`, the column layout (`property_order`, `hidden_properties`, per-column widths, alignments, and `column_styles` — the per-type look + date / weekday / time format choices; these display formats live per-VIEW here, a deliberate divergence from Swift's def-level format keys), the `sort` (a multi-key list), the `filter` (a nested group), the `group` config plus the view-level `group_order` (the manual structural band order — one flat set-id array across every nesting level; property band order lives on `group.order`), and display options (card size, collapsed-group state, cover and banner toggles). A view also records its `format` (Standard / Compact — the table density style). The **active view is tracked per-machine** in `.nexus/activeViews.json` — a container-to-view map kept out of the synced sidecar, so switching views never churns the shared file. The per-container **ViewDropdown** (a toolbar button left of the trio, glyph = the active view's icon) opens the **ViewPane** dropdown to switch the active view; view CRUD — create (title-only "Untitled"), rename, duplicate, delete, reorder — persists to the sidecar. Two per-container presentation settings ride the sidecar and sync: `view_button` (the button's Show/Hide Title) and `view_style` (Dropdown / Toolbar). A container never presents an empty `views[]`: an app-created container is seeded with its default view on disk, and an empty view-bearing container mints its default on first entry.

#### II. The Pipeline

One pure pipeline feeds the renderer — **columns → filter → group → sort** — reading each Page's frontmatter (loaded lazily per container over a batch IPC), never the index.

- **Filter** — a recursive group of rules under Match All / Any, nesting groups inside groups for mixed AND/OR expressions, with type-aware operators; an unknown operator is a no-op.

- **Group** — structural (by Set / Sub-Set disclosure), flat, or by a property. Groupable types are Select, Status, Checkbox, and Date; a date groups by day, week, month, or year; option order follows the schema until a band drag snapshots a manual order (view-owned — `group_order` for structural bands at every nesting level, `group.order` + manual mode for property bands; unlisted entries trail in derived order). A non-groupable property falls back to structural. Value-less rows render as a header-less flattened tail pinned last — no "None" band.

- **Sort** — a multi-key list applied in priority order, stable on ties, with per-type comparators (Select and Status by option order, dates chronological, checkbox by rank, text case-insensitive).

- **Columns** — resolved from the view's `property_order` against the schema.

#### II. Renderers

The **Table** renderer draws the resolved groups as nested tables, with structural Sub-Set nesting and row-click selection — its layout, column ergonomics, and row/group chrome are its own doc (`TableView.md`). The Cards, List, Gallery, Calendar, and Timeline renderers are Pending.

#### II. Surfaces

Two dropdowns configure a container, both scoped to a selected Collection or depth-1 Set:

- The **ViewPane** (opened by the ViewDropdown) is a navigation dropdown: a row per saved view (click switches the active view; the row's chevron opens that view's **ViewSettings**) over a footer (create · more). Right-clicking the ViewDropdown opens a native menu for its two presentation settings (Show/Hide Title · Style).
- **ViewSettings** is the shared per-view editor, reachable two ways — the ViewPane row's chevron (the *full* door, carrying the ⋮ Duplicate/Delete and the leaf rows) or the SettingsPane's Layout entry (the *flat* door, for the active view, minus the ⋮ and leafs). It holds the view's icon + name, a 3×2 type-picker grid, and the type's options — for Table, the Layout leaf (order + visibility) and the **Format** control (Standard / Compact).
- The **SettingsPane** (the toolbar sliders button) carries the container's identity + config: **Configuration** (the collection's **Open In** — full-page vs page-preview, Collection-owned), **Properties** (the schema editor → `Properties.md`), **Visibility**, and the Layout / Group / Filter / Sort leafs. Properties and Visibility are built; the rest open blank leafs.

#### II. Visibility Pane

The active view's shown/hidden split (`HiddenPane`). **Contexts** sit on top as a static block — always the three tiers in the fixed Areas · Topics · Projects order, never draggable; hiding one ghosts it in place (the shared ghost opacity) rather than relocating it. Below a divider the properties run as **one list with no heading**: the shown rows in view order, then the hidden rows ghosted after them in COLLECTION order (Modified trailing) — the ghost itself is the boundary. Title appears nowhere (it can't hide, and its reorder belongs to the table's column drag).

Drags carry the shared drag language. A drop **into the shown zone is positional** — a shown row reorders and a hidden row unhides at the slot, both under the drop line — and rewrites the view's `property_order`, with the shown zone acting as a window into the full column order so Title and the tiers hold their absolute slots. A shown row dropped **into the hidden zone is a membership drop** — it hides, shown as the area highlight with no line, since the hidden order is derived, never authored (hidden rows don't reorder within their zone). Every row carries a trailing eye toggle: open at rest on shown rows, slashed on hidden ones, hover swapping both the glyph and the color to preview the flip (hidden rows run the pair in reverse). Hiding only flags `hidden_properties` — `property_order` keeps the slot — so an eye-unhide restores the property where it was; only a drag-in chooses a new position. Writes save the whole view and refetch, so the table behind the dropdown updates on the same beat; the table's optimistic column-order override drops once the canonical view confirms it, keeping the two writers coherent.

### Pending

**Cards, List, Gallery, Calendar, and Timeline Renderers:** The five non-Table view types. The type registry carries all six; only Table draws.

**View-Settings Editing Panes:** The Group, Sort, and Filter leafs, and the Layout leaf's order + visibility section (which folds the Visibility pane in, gated on its own design). The Format control persists Standard / Compact but is visually inert until the Compact table style lands. The pipeline already honors these configs from the sidecar, so the gap is authoring them — Properties and Visibility (the standalone SettingsPane entry) are reachable.

**ViewBar:** The `view_style` Toolbar option — an inline view-switcher bar as an alternative to the dropdown. The setting persists; the surface builds later.

### Prospects

**In-Line View Embeds in Pages:** A saved view embedded as a live widget inside a Page body. Composed-block surfaces (Contexts, Homepage) get embeds; Page bodies don't.
