### Views

A view is a saved presentation of a [Collection's](Collections.md) (or a depth-1 Set's) Pages. It never modifies its source — filtering, grouping, and sorting are presentation only.

Every Collection or depth-1 Set carries an ordered list of saved views, and one pure pipeline drives every renderer. Five view types are modeled: **Table**, **Board**, **List**, **Cards**, and **Gallery**.

### Features

#### II. Saved-View Model

Each container's sidecar holds an ordered `views[]`. A saved view records its `id` (a ULID), `name`, `icon`, renderer `type`, the `property_order` and `hidden_properties` (column layout), the `sort` (a multi-key list), the `filter` (a nested group), the `group` config, and display options (card size, collapsed-group state, cover and banner toggles). The **active view is tracked per-machine** in `.nexus/activeViews.json` — a container-to-view map kept out of the synced sidecar, so switching views never churns the shared file. A toolbar dropdown switches the active view; view CRUD — create, rename, duplicate, delete, reorder — persists to the sidecar.

#### II. The Pipeline

One pure pipeline feeds the renderer — **columns → filter → group → sort** — reading each Page's frontmatter (loaded lazily per container over a batch IPC), never the index.

- **Filter** — a recursive group of rules under Match All / Any, nesting groups inside groups for mixed AND/OR expressions, with type-aware operators; an unknown operator is a no-op.

- **Group** — structural (by Set / Sub-Set disclosure), flat, or by a property. Groupable types are Select, Status, Checkbox, and Date; a date groups by day, week, month, or year; option order follows the schema. A non-groupable property falls back to structural.

- **Sort** — a multi-key list applied in priority order, stable on ties, with per-type comparators (Select and Status by option order, dates chronological, checkbox by rank, text case-insensitive).

- **Columns** — resolved from the view's `property_order` against the schema.

#### II. Renderers

The **Table** renderer draws the resolved groups as nested tables, with structural Sub-Set nesting and row-click selection. The Board, List, Cards, and Gallery renderers are Pending.

#### II. View Settings

The view-settings dropdown is scoped to the selected container — a Collection or depth-1 Set gets the view pane, other surfaces get none. Its root menu pushes to per-pane editors, of which the **Properties** pane (the schema editor → `Properties.md`) is built; the remaining panes are Pending.

### Pending

**Board, List, Cards, and Gallery Renderers:** The four non-Table view types. The type enum carries all five; only Table draws.

**View-Settings Editing Panes:** The Filter, Group, Sort, Layout, and Visibility panes. The pipeline already honors these configs from the sidecar, so the gap is authoring them — only the Properties pane is reachable.

**Rich Table Cells:** Type-aware cell rendering (Select / Status / relation chips, checkboxes), inline cell editing, and column resize and reorder. The table renders plain-text cells.

### Prospects

**In-Line View Embeds in Pages:** A saved view embedded as a live widget inside a Page body. Composed-block surfaces (Contexts, Homepage) get embeds; Page bodies don't.
