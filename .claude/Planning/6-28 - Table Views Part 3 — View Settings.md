## Table Views — Part 3 (View Settings) — Status + Plan

The View Settings surface: the glass dropdown behind the toolbar Settings button, its per-pane sub-navigation, and the wiring from those panes to the schema + view-persistence layers shipped in Part 1. Built iteratively against the live Swift app as the design reference; this doc is the running status (what's built) + the remaining pane work.

### Architecture (locked)

- **The toolbar trio is generic chrome — not pane-bound.** A pure `viewSettingsScope(selection)` (`Detail/ViewSettingsScope.ts`) maps the in-window content view to a scope (`view | page | context | none`); `SettingsDropdown` switches on it to choose the pane. Adding a future surface's pane is a new scope case + a switch arm, never a change to the button. Mirrors Swift's `ViewSettingsScope` + `ViewSettingsButton(scope:)`, leaner (React's `ViewPane` re-resolves the selection from the store, so the scope carries no payload).

- **One shared dropdown shell.** `SettingsDropdown` owns the anchor + glass `MenuSurface`; both the Settings pane and the Navigation panel render through `MenuSurface` so every toolbar dropdown shares one frosted-glass chrome + the standard gutter (`MENU_GUTTER`, matched to the sidebar edge padding).

- **Dropdown glass = native CSS frost, not liquid.** `GlassPane` (the `MenuSurface` material) renders the native frost recipe, NOT `@samasante/liquid-glass` — see History (the liquid lens fought the dropdown case; the frost is what the surfaces/window already use). The frost is **baked static into `PANE_FROST`**; the temporary ⌘D `GlassTuner` was removed.

- **Pane navigation is a sliding push/back stack — at every depth.** `ViewPane` is the Collection/Set root menu (icon+title header → Properties · Visibility · Layout · Group · Filter · Sort, each with its standard icon); `PaneSlider` slides root↔detail with the **width+height resize on the same beat as the slide**, min floors + a height cap (Nathan's knobs, live in `ViewPane.tsx`) past which a pane scrolls under the shared scroll-edge fade. PropertiesPane's own subviews ride a NESTED PaneSlider, so list→editor/type-picker pushes slide identically with zero per-window wiring. The back-row heading (`‹`) titles the current pane (subline type, gutter-flush, `--label-secondary`).

### Built

- **Settings dropdown shell** — `SettingsDropdown` (scope-routed), `ViewPane` root menu (header + the six rows, one uniform list with standard icons), `PaneSlider` (slide + synced resize + 200px min-height + bottom-pinned footers), `MenuSurface` shared shell, `InteractionField` + `Switch` primitives, the `--input-field` token alias (name + icon fields).
- **Properties pane — the full assign surface (7-2, shipped)** — assigned rows (chevron → the per-property editor) over the bottom-pinned **All Properties** disclosure (rises open; unassigned registry defs in the nexus order, `+` promotes); the two-region drag (reorder assigned = collection order, reorder All Properties = nexus order, drag-in assigns at the slot, drag-out Removes with the area highlight); the header's `square-plus` create → type picker; row right-click Rename (inline, the `renamingProperty` channel) · Remove; the editor's `‹ Name ⋮` header (Remove · pane-gated Delete behind main's confirm). Routes to `schema:add/rename/reorder/delete(=Remove)/assign/changeType` + `registry:reorder` + `property:delete` (page-schema CRUD on the Collection sidecar; a Set resolves its ancestor Collection's schema). Select/Multi-Select creation seeds a starter option (`defaultSelectSeed`), mirroring the status seed. Per-type label + icon hoisted to one `PropertyTypes.tsx` registry; `url`'s name is "Link".
- **Standard icons** — panes + property types wired to the catalog (`Features/Icons.md`); back-row + footer share the `flushAffordance` (subline, `--label-secondary`).
- **Navigation panel** — rendered on the same frost `MenuSurface`; currently the in-context mount for the new **Switch** (Figma toggle on `GlassSegment`).
- **Glass system** — `GlassPane` → native frost (baked `PANE_FROST`; the ⌘D tuner + `usePaneFrost` store removed). The small-control liquid glass `GlassSegment` was split out for the switch knob.

### Pending

- **Properties rich editor** — per-type options / status-group editor (the Status, Multi-Select, and Select PropertyPanes are design-ready in Figma — first in line), format + display pickers, change-type (with the lossy-conversion confirm), duplicate (needs a backend `duplicate` fn), **checkbox On/Off state naming** (Part 2 L-2 routes disclosure titles to these once they exist).
- **Grouping pane** — grouping toggle + Group-By picker + order-mode / date-granularity / empty-placement / hide-empty controls, wired to `GroupConfig`.
- **Sort pane** — multi-key criteria list (add/remove/reorder, direction), the `isSortable` picker filter (excludes relation/file/last-edited per Part-1 note), wired to `SortCriterion[]`.
- **Filter pane** — rule builder + the operator picker (narrower than the evaluator matrix), AND/OR (incl. nested groups), wired to `FilterGroup`.
- **Layout pane** — `Format: Table ›` view-type picker; **Hide Page Icons** + **Hide Borders** toggles (two new `SavedView` fields, icons default ON); **Table Size: Standard | Compact** (routes typography; ships default-Compact, this pane is its eventual control); the **Display-As toggle** (switch a property's `display_as` — the renders already exist as chip forms, only the toggle is unbuilt); **new-items placement** (`newItemsTo: 'top' | 'bottom'`, default bottom); "Open Pages In" (`open_in`). Detail → Part 2 (E-5, K-1, L-5, M-1/Q-3).
- **Visibility pane** — column show/hide + order; the **un-hide path** for Part 2's right-click "Hide Property" (which writes `hidden_properties`).
- **View management** — rename / duplicate / delete a view; the active-view switcher — wiring the already-shipped `views:save/reorder/delete` + `activeViews:get/set` IPC (Part 1) to the UI.
- **Switch wiring** — the Switch is built + mounted in Navigation for critique; the Grouping/Layout/Visibility panes will consume it (hide-empty, show-cover/banner, **Hide Page Icons / Hide Borders**, column show/hide). Replace the Navigation placeholder mount once a real pane uses it.

### Notes

- Built against `main` (Part 1 merged). Renderer/CSS changes HMR; **main-process changes (the `schema:*` IPC, select seed) need a full dev restart**, not ⌘R.
- Part 2 (table UIX + chips) is the sibling track — now **fully specced** (`6-29 — Table Views Part 2 — UIX Redo + Label Fix`, review-folded). Both consume the Part-1 seams and share contracts this surface must honor: the new `SavedView` fields (`hide_page_icons` / `hide_borders`), the `display_as` model (Part 2 wires *reading* it; the Layout pane wires the *toggle*), the **Table Size** typography routing, and the per-machine view-order cache. Part 2's **NexusLabels restructure** (B: tiers → `area`/`topic`/`project` LabelPairs, drop `sidebarSections`) is a shared prerequisite — panes reading tier labels use the new `tierLabel` helper.
