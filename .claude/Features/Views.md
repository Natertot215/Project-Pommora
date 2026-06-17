## Views

The detail-pane surfacing layer for Pages. Every storage container (Page Type / Page Collection) carries one or more **saved views** in its sidecar; a toolbar Views dropdown switches between them. Two renderers ship — a **Table** and a **Gallery** — both fed by one pure in-memory pipeline.

---

#### SavedView v2 (sidecar schema)

Each container's `views[]` holds `SavedView` objects (snake_case, all new fields `decodeIfPresent`):

```json
{
  "id": "view_<ULID>",
  "name": "All Pages",
  "icon": "tablecells",
  "type": "table | board | list | cards | gallery",
  "property_order": ["_title", "prop_<ulid>", "_tier1", "_modified_at"],
  "hidden_properties": ["prop_<ulid>"],
  "sort": [{ "property_id": "_modified_at", "direction": "descending" }],
  "filter": { "match": "all | any", "rules": [{ "property_id": "...", "op": "...", "value": "..." }] },
  "group": { "kind": "structural" },
  "column_widths": { "_title": 240.0 },
  "collapsed_groups": ["<containerULID | option value | _ungrouped>"],
  "card_size": "small | medium | large",
  "show_cover": false,
  "show_banner": true
}
```

- **`property_order`** is one ordered list of every column id (including `_title`, the tier columns, `_modified_at`) paired with the **`hidden_properties`** set — replacing the old two-array visible/hidden model. Legacy `visible_properties` decodes once (`property_order = ["_title"] + legacy`, decode-only). Unaccounted schema properties append at resolution. `ReservedPropertyID` carries `title = "_title"`; Title is movable to any position, never hideable. The `cover` field is never a column.
- **`group`** (GroupConfig) is a tagged object discriminated on `kind`: `{"kind":"structural"}` | `{"kind":"property", "property_id":"…", "order_mode":"configured|reversed|manual", "order":[…], "date_granularity":"day|week|month|year", "empty_placement":"top|bottom", "hide_empty_groups":bool}` | `{"kind":"flat"}` → Swift cases `.structural` / `.property(PropertyGrouping)` / `.flat`. The extra `PropertyGrouping` fields are additive (decode-with-default; legacy `order` stays dormant until `order_mode == manual`). `group == nil` and any unknown `kind` decode to `.structural` (lenient — a throw would poison the whole sidecar). Full model → `Planning/06-15-Grouping-Redesign.md`.
- **Sort presets** encode as reserved property ids: Title → `_title`, Created → `_id` ascending (ULID = creation order), Recent → `_modified_at` descending. Stored as the existing `[SortCriterion]?` array (UI restricts to one). `PageType.default_sort` folds into the minted default view's `sort`, keeps decoding, is never written again.
- **`card_size`** small/medium/large maps to a fixed cards-per-row count, smaller cards packing more per row.
- **`show_cover`** defaults **OFF** (nil/false = hidden). **`show_banner`** defaults **ON when a container banner exists** (the toggle exists to hide it per view).
- **No SQLite changes** — views are sidecar-only.

---

#### View Pipeline

One pure, unit-tested pipeline feeds both renderers: **fetch → filter → group → sort within groups → resolved groups**. It has no SwiftUI dependency.

- **Fetch** — reads the in-memory manager caches (already manual-order-resolved) and stamps each item with its parent + Set label. Runs entirely off cached frontmatter, so any property edit recomputes the view instantly with no extra disk reads (the SQLite index isn't in this path).
- **Filter** — applies the flat rule list under Match All/Any with conservative per-type operators (full operator matrix in the spec); an unknown operator is a no-op.
- **Group** — produces the resolved groups. `.structural` (the default): vault scope groups by Collection with Sets nested as children; collection scope groups by Set plus an ungrouped root band (zero Sets → one ungrouped band, no header — the flat look). `.property` (groupable types = Select / Status / Checkbox / Date — single-value only) flattens to buckets ordered by the chosen order mode: configured (schema-option order; Date by the chosen granularity bucket, Checkbox Unchecked-first), reversed, or manual (an explicit override order). The "No [Property]" bucket is placed by the empty-placement setting and dropped by hide-empty-groups; Checkbox routes an unset value to Unchecked (no nil bucket). A missing / non-groupable property falls back to `.structural`. `.flat` is a single group.
- **Sort** — sorts within each group; nil means manual order. Title is case-insensitive, Created is creation-order (ULID), Recent is modified-date with a created-date fallback, select/status sort by schema option order.

Mutations route through existing manager APIs: reorder (collection/set/vault-root), structural move, and property rewrite.

A prerequisite ordering fix underpins this: a view-config save must read the sidecar fresh before persisting, so a whole-struct save can't clobber a page reorder that landed between reads.

---

#### Table Renderer

The table renderer is a native AppKit outline/table view (`NSOutlineView`) styled to match the native macOS Table look, with a few deliberate behavior tweaks. SwiftUI cell content is hosted inside the AppKit rows, so cell rendering and editing reuse the same property editors as the rest of the app.

- **Group headers** render as native-style disclosure rows (chevron + grouping-value label + count) that scroll with the content rather than pinning. The container affordances the old Collection/Set rows carried (Open / Edit Title / Edit Icon / Delete) migrate onto these group rows.
- **Rows** reuse the shared property cell editors unchanged (display-first, commit-on-dismiss popovers). Native alternating-row striping is on. **Rename is context-menu only** (no click-to-edit on Title cells); the icon click opens the icon picker. The table has no cover access at all.
- **Columns** resolve from the view's property order + schema, each header carrying its property-type glyph. Columns resize by dragging a trailing handle down to a minimum width, with the resize persisted on release; dragging a header re-arranges column order; right-clicking a header offers Hide Column (Title exempt).
- **Selection + keyboard** — multi-select with an anchor; plain / ⌘ / ⇧ click; arrow-key navigation and type-select; double-click opens the page.

---

#### Gallery Renderer

A grid of cards, one section per resolved group (same disclosure headers + collapse as the table).

- **Card anatomy** — cover area (only when Show Cover is on; empty fill when no cover is set) → header (icon + title) → property zones: **chips** (select / multiSelect / status / tier relations + the Set label chip at vault scope), **meta** (dates / number / checkbox), **links** (url). Zones order by the view's property order, respect the hidden set, exclude cover always, and are **fully interactive** — the same popover editors as table cells assign and remove values on the card.
- **Interaction** — single click selects; **double-click on the title text renames inline; double-click anywhere else opens** the page; icon click edits the icon; right-click the card = page context menu; right-click the visible cover area = Set / Change / Remove Cover.
- Covers load through an image pipeline that resizes and disk-caches across launches.

---

#### Covers + Banners

- **Cover** — a root `cover` frontmatter field on the page (nexus-relative path), written as frontmatter (never as a property). It **never appears in any properties UI** — not Edit Properties, not the Layout visibility list, not the inspector. Access points: the Layout pane's Display toggle, right-clicking a card's visible cover area, and (a future page-editor session) inline on the page.
- **Banner** — a `banner` field on the container sidecar, hideable per view via Show Banner. With no banner set, the bold detail title sits as plain chrome above the content; with one set, a full-width image bleeds edge-to-edge under the surrounding chrome (the macOS 26 background-extension effect) with the title overlaid at the bottom-leading corner. Add Banner is a hover-revealed button in the no-banner state opening a file picker; once set, a Change / Remove menu manages it.
- Image files are copied into a per-entity assets folder under the Nexus, de-duplicated on filename collision.

---

#### Views Dropdown + Multi-View Model

- A window-toolbar Views button sits left of the settings·nav·inspector trio (popover pattern) — an icon-only button showing the active view's icon, opening the dropdown popover. The toolbar is hosted on the detail column as two glass capsules (Views pill | trio).
- The dropdown is one popover of custom rows: icon + view name on the left, a muted right-side type label ("Table" / "Gallery | Small" — type plus, for gallery, the card size) that is itself a button toggling an **inline type-switcher** (Table + Gallery active; Board/List/Cards muted, written in place). Row click = set active + dismiss. Name edits inline (double-click), icon via the icon picker. Context menu: Rename / Duplicate / Delete (at least one view must remain). Footer "New View" mints an untitled table view.
- **Active view persists per container** (an active-view map keyed by container in per-Nexus state), surfaced by an observable store; a missing entry resolves to the first view. All detail-view rendering and every View-Settings pane resolve the active view through this store.

The toolbar / Views-button / banner chrome is current-state observation, not settled truth — open unknowns and next steps live in the Views-UIX planning doc, not here.

---

#### View Settings Panes

The View Settings popover is active-view-scoped:

- **Edit Properties** — **schema-only**: add / rename / type-change / delete / reorder properties. Tier columns and Modified are excluded (they're non-editable); it carries no visibility toggles.
- **Layout** — per-view display config: **Display Banner** toggle, **Card Size** (gallery), the **Property Visibility** eye-list (per-view show/hide + drag-order over ALL columns — user properties, the tier columns, and Modified; Title pinned non-hideable; cover never listed), and a muted **Wrap Text** row (table; dynamic row heights are a later pass). The vault-scoped open-in selector is labeled **Open Pages In**.
- **Sort** — single picker: Manual, Title A→Z / Z→A, Created, Recent, or any property asc/desc.
- **Filter** — flat rule list + Match All/Any.
- **Group** — a **Grouping** toggle (off = the `.structural` file-system default) that discloses an inline property picker (Select / Status / Checkbox / Date); a per-type **Order** popout, a **Date By** popout (Day/Week/Month/Year), a manual **Options** reorder list (Select/Status), and a bottom-pinned empty-group footer (Hide empty groups · Empty group Top/Bottom). Full spec → `Planning/06-15-Grouping-Redesign.md`. (View-side rendering of the groups + group-header manual drag is still pending — see the plan.)

---

#### Drag Semantics

Drag runs on the macOS 26 system drag-session APIs: page sources + drop destinations, with a live insertion line + group-header highlight during hover. Only page rows are drag sources (group rows are not). A pure, tested planner resolves intent:

- **Reorder** — manual-only (active when sort is manual) and same-container; writes a page reorder.
- **Structural-group drop** — a real file move.
- **Property-group drop** — a frontmatter rewrite of that property's value (the ungrouped bucket clears it).

The same insertion-line mechanics apply to the settings reorder surfaces (Select/Status option editors). Drop targets are kept out of the list view (an unfixed macOS bug). A hand-rolled gesture coordinator stays isolated as a fallback if the system feel is ever rejected.

---

#### Deferred

Board / List / Cards renderers (their type cases carry through the data model); multi-level sort chains; nested filter groups; page-editor rendering of the cover banner; functional table text-wrapping (dynamic row heights).
