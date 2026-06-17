## Views

The detail-pane surfacing layer for Pages. Every storage container (Page Type / Page Collection) carries one or more **saved views** in its sidecar; a toolbar Views dropdown switches between them. Two renderers ship — a **Table** and a **Gallery** — both fed by one pure in-memory pipeline.

---

#### Saved-view model

Each container's sidecar holds an ordered list of saved views. A view records its name and icon, its renderer type, the property layout, and the sort / filter / group / display config. New fields decode leniently with sensible defaults, so an older sidecar never fails to load. Views are sidecar-only — no SQLite changes.

- **Property layout** is one ordered list of every column — Title, the tier columns, Modified, and user properties — paired with a hidden-column set, rather than separate visible and hidden arrays. Title is movable but never hideable; the cover is never a column. A property missing from the order appends at resolution.
- **Grouping** is a tagged config: structural (default), property-based, or flat. Property grouping additionally carries its order mode, date granularity, empty-bucket placement, and a hide-empty toggle. A nil or unrecognized grouping decodes to structural — a throw would poison the whole sidecar. Full model → `Planning/06-15-Grouping-Redesign.md`.
- **Sort presets** encode as reserved column ids — Title, Created (creation order), Recent (modified date) — stored as a single-criterion list.
- **Card size** (gallery) maps small/medium/large to a fixed cards-per-row count, smaller cards packing more per row.
- **Show Cover** defaults off; **Show Banner** defaults on whenever the container has a banner (the toggle hides it per view).

---

#### View pipeline

One pure, unit-tested pipeline with no SwiftUI dependency feeds both renderers: **fetch → filter → group → sort within groups → resolved groups**.

- **Fetch** reads the in-memory manager caches (already manual-order-resolved) and stamps each item with its parent and Set label. It runs entirely off cached frontmatter, so any property edit recomputes the view instantly with no extra disk reads — the SQLite index isn't in this path.
- **Filter** applies the flat rule list under Match All / Any with conservative per-type operators; an unknown operator is a no-op.
- **Group** produces the resolved groups. **Structural** (default): at vault scope, group by Collection with Sets nested as children; at collection scope, group by Set plus an ungrouped root band (zero Sets collapses to one headerless band — the flat look). **Property** (groupable types only, single-value) flattens to buckets ordered by the chosen mode — configured, reversed, or explicit manual order. The empty bucket follows the empty-placement setting and is dropped by hide-empty; an unset checkbox routes to its false bucket rather than an empty one. A missing or non-groupable property falls back to structural. **Flat** is a single group.
- **Sort** orders within each group; nil means manual order, otherwise the relevant preset or property comparator applies.

Mutations route through existing manager APIs (reorder, structural move, property rewrite). A view-config save reads the sidecar fresh before persisting, so a whole-struct save can't clobber a page reorder that landed between reads.

---

#### Table renderer

A native AppKit outline/table view styled to match the macOS Table look, with a few deliberate behavior tweaks. SwiftUI cell content is hosted inside the AppKit rows, so cells reuse the same property editors as the rest of the app.

- **Group headers** render as native-style disclosure rows (chevron + grouping value + count) that scroll with the content rather than pinning. The container affordances the old Collection/Set rows carried (Open / Edit Title / Edit Icon / Delete) migrate onto these group rows.
- **Rows** reuse the shared property cell editors unchanged (display-first, commit-on-dismiss popovers); native alternating striping is on. Rename is context-menu only — no click-to-edit on the Title cell; the icon click opens the icon picker. The table has no cover access.
- **Columns** resolve from the view's property order plus schema, each header carrying its property-type glyph. Dragging a trailing handle resizes to a minimum width with the result persisted on release; dragging a header reorders columns; right-click offers Hide Column (Title exempt).
- **Selection + keyboard** — multi-select with an anchor (plain / modifier / shift click), arrow navigation, type-select, double-click to open.

---

#### Gallery renderer

A grid of cards, one section per resolved group (same disclosure headers and collapse as the table).

- **Card anatomy** — cover area (only when Show Cover is on; an empty fill when no cover is set) → header (icon + title) → property zones: **chips** (select / multi-select / status / tier relations, plus the Set-label chip at vault scope), **meta** (dates / number / checkbox), **links** (url). Zones follow the view's property order, respect the hidden set, always exclude cover, and are fully interactive — the same popover editors as table cells assign and remove values on the card.
- **Interaction** — single click selects; double-click on the title renames inline, double-click elsewhere opens; the icon click edits the icon; right-click the card is the page context menu; right-click the visible cover area is Set / Change / Remove Cover.
- Covers load through an image pipeline that resizes and disk-caches across launches.

---

#### Covers + banners

- **Cover** — a root frontmatter field on the page (a nexus-relative path), written as frontmatter, never as a property. It never appears in any properties UI. Access points: the Layout pane's Display toggle, right-clicking a card's visible cover area, and (a future session) inline on the page.
- **Banner** — a field on the container sidecar, hideable per view. With no banner, the bold detail title sits as plain chrome above the content; with one, a full-width image bleeds edge-to-edge under the surrounding chrome (the system background-extension effect) with the title overlaid bottom-leading. Add Banner is a hover-revealed button in the no-banner state; once set, a Change / Remove menu manages it.
- Image files are copied into a per-entity assets folder under the Nexus, de-duplicated on filename collision.

---

#### Views dropdown + multi-view model

- A window-toolbar Views button shows the active view's icon and opens the dropdown popover; the toolbar is hosted on the detail column as two glass capsules (Views pill, settings·nav·inspector trio).
- The dropdown is a popover of custom rows: icon + name on the left, a muted right-side type label (renderer, plus card size for gallery) that doubles as a button toggling an inline type-switcher (Table and Gallery active; the deferred renderers shown muted in place). Row click sets active and dismisses; name edits inline; icon via the picker. Context menu: Rename / Duplicate / Delete (at least one view must remain). A footer mints a new untitled table view.
- **Active view persists per container** — an active-view map in per-Nexus state, surfaced by an observable store; a missing entry resolves to the first view. All detail rendering and every View-Settings pane resolve the active view through this store.

Toolbar / Views-button / banner chrome is current-state observation, not settled truth — open unknowns live in the Views-UIX planning doc.

---

#### View settings panes

The View Settings popover is active-view-scoped:

- **Edit Properties** — schema-only: add / rename / type-change / delete / reorder properties. The tier columns and Modified are excluded (non-editable); it carries no visibility toggles.
- **Layout** — per-view display config: Display Banner, Card Size (gallery), the Property Visibility eye-list (per-view show/hide plus drag-order over all columns — user properties, tier columns, and Modified; Title pinned non-hideable; cover never listed), and a muted Wrap Text row (dynamic row heights are a later pass). The vault-scoped open-in selector is labeled Open Pages In.
- **Sort** — a single picker: Manual, Title A→Z / Z→A, Created, Recent, or any property ascending/descending.
- **Filter** — flat rule list plus Match All / Any.
- **Group** — a Grouping toggle (off is the structural default) disclosing an inline property picker, a per-type Order popout, a Date By popout, a manual Options reorder list, and a bottom-pinned empty-group footer (hide-empty, empty Top/Bottom). Full spec → `Planning/06-15-Grouping-Redesign.md`. View-side rendering of the groups plus group-header manual drag is still pending — see the plan.

---

#### Drag semantics

Drag runs on the system drag-session APIs — page sources and drop destinations, with a live insertion line and group-header highlight on hover. Only page rows are drag sources (group rows are not). A pure, tested planner resolves intent:

- **Reorder** — manual-only (active when sort is manual) and same-container; writes a page reorder.
- **Structural-group drop** — a real file move.
- **Property-group drop** — a frontmatter rewrite of that property's value (the ungrouped bucket clears it).

The same insertion-line mechanics apply to the settings reorder surfaces. Drop targets are kept out of the list view (an unfixed system bug). A hand-rolled gesture coordinator stays isolated as a fallback if the system feel is ever rejected.

---

#### Deferred

Board / List / Cards renderers (their type cases carry through the data model); multi-level sort chains; nested filter groups; page-editor rendering of the cover banner; functional table text-wrapping (dynamic row heights).
