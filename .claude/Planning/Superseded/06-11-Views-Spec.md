## Views — Ratified Spec

**Status:** ratified design for the Views cluster (2026-06-11) — supersedes this file's earlier pre-design findings ledger. Consolidates the interview-locked decisions, the platform/SDK research (verified against the macOS 26.5 SDK on this machine and the Xcode 26 toolchain), and the codebase audits. The implementation plan is written separately from this spec.

**Verified ground facts this spec builds on:** deployment target is **macOS 26.4** (all pbxproj configurations) — every macOS 26 API below is usable un-gated. `PageMeta.frontmatter` carries the full properties dict + tiers + dates, so the view pipeline runs in-memory with zero extra disk reads. `PropertyCellEditor` is already display-first with popover editors (editor-on-demand), reusable as-is.

### Scope

- **Table + Gallery ship fully.** Board / List / Cards remain `ViewType` enum cases the data model carries; their UI comes in later passes.
- Ships with them: multi-saved-views per container with a toolbar dropdown switcher, per-view sort / filter / group / column config, the per-view reorder engine, page cover images + container banners, and the merged Edit Properties pane (Property Visibility pane retired).
- Out of scope here: page-editor rendering of the cover banner (a MarkdownPM session), Board/List/Cards UI, multi-level sort chains, nested filter groups, FTS5 wiring (same release bucket, separate infra work).

### Decision Ledger (interview, 2026-06-11)

1. **Custom table renderer** — a visual 1-1 duplicate of native macOS `Table`. Native `Table` is retired from detail views: SDK-verified it still has no row reorder and no column-width readback, has active Tahoe memory-leak bugs, and the Introspect rescue breaks SwiftUI's own rendering.
2. **Title column**: movable to any position, never hideable. `_modified_at` becomes hideable (sort no longer depends on column visibility).
3. **Gallery card sizes** S / M / L = exactly 8 / 6 / 4 cards per row.
4. **Cover** = reserved `cover` frontmatter field (nexus-relative path). Cover DISPLAY is a per-view toggle (`show_cover`, default OFF); toggled on with no cover set, cards show an empty fill. **The cover field never appears in any properties UI** (not Edit Properties, not visibility lists, not the inspector). Access: gallery view settings, right-clicking a card's visible cover area (Set / Change / Remove), and — later MarkdownPM session — inline on the page. No cover access from table view. **Banner** = `banner` field on `_pagetype.json` / `_pagecollection.json`: when unset, the banner area does not exist at all; when set, a full-width image area renders above the container title (header zone grows taller) in every view type, hideable per view (`show_banner`). Add Banner = a small floating button that appears only when no banner is set (the fullscreen page add-icon pattern) → file picker. Image files are copied into `.nexus//assets//<entityID>//`.
5. **Grouping**: `GroupConfig` is discriminated structural-or-property. Defaults — Vault views group by Collection (table: Sets nested inside the Collection disclosure; gallery: Collection sections only, each card carrying a Set label chip), Collection views group by Set + an ungrouped root band. Property grouping replaces and flattens structural grouping. Sort applies within groups.
6. **Both group-drop behaviors ship**: drop into a property group rewrites that property value in frontmatter; drop into a structural group performs a real file move.
7. **Manual order is the shared container order** (the sidebar mirrors it) — view reorders write through the managers to the owning container sidecar. Manual reorder is available only when sort = Manual. Sorts / filters / groups are pure view-level overlays that never touch file locations.
8. **Sort**: one active sort per view — Manual, Title A→Z / Z→A, Created, Recent, or any property asc//desc; select//status compare by schema option order. Stored as the existing `[SortCriterion]?` array (UI restricts to one) so multi-sort needs no migration.
9. **Filters**: flat rule list + Match All//Any (existing `FilterGroup` shape), conservative per-type operators. Edited in the View Settings popover, whose content is active-view-scoped.
10. **View switching = toolbar Views dropdown** (not tabs — supersedes the roadmap's earlier phrasing): rows of icon + view title with a muted right-side type label (**"Table", "Gallery | Small"** — pipe + full size word) that is itself a disclosure opening an inline type switcher; "New View" footer mints **"Untitled View"** (type Table); rename / duplicate / delete via row context menu (≥1 view guard). The toolbar button itself has two display modes — icon-only (65×36pt) or liquid-glass icon + active-view title — toggled via right-click on the button, persisted in `state.json`. Last-active view per container persists in `state.json`.
11. **A new Layout pane holds per-view display config** (exact UI pending a Figma pass): Display Banner toggle, Card Size (gallery), the **Property Visibility** list (per-view eye toggles + drag order over ALL columns — user properties, the tier columns, and Modified; `_title` pinned non-hideable; cover never listed), and a muted "Wrap Text" row (table; functional wrapping is a later pass). **Edit Properties is schema-only** — tier columns and Modified are removed from its list (non-editable), and it carries no visibility toggles. The standalone Property Visibility pane is retired.
12. **Per-view persistence in `SavedView`** (sidecar): property order + hidden set, sort, filter, group, column widths (written on resize-end), collapsed group IDs, card size, cover/banner display toggles.
13. **Type-switchable in place** — same `SavedView`, change `type`, shared config follows.
14. **Inline editing**: table rows rename via context menu (no click-to-edit Title cells); cards rename via double-click ON THE TITLE TEXT (double-click anywhere else opens the page; single click selects); clicking an icon edits the icon — standard across both view types; the saved view's own name + icon edit inline on the dropdown rows. **Card property zones are fully interactive** — values assignable and removable on the card via the same popover editors as table cells. Property edits reflect instantly in active sort/group/filter (the pipeline recomputes from `@Observable` manager state).
15. **Native-first bias**: prefer what Apple gives us for free over hand-rolled mechanics, always — custom only where the SDK verifiably can't deliver.

### On-Disk Schema

**SavedView v2** (snake_case, all new fields `decodeIfPresent`):

```json
{
  "id": "view_<ULID>",
  "name": "All Pages",
  "icon": "tablecells",
  "type": "table | board | list | cards | gallery",
  "property_order": ["_title", "prop_<ulid>", "_tier1", "_modified_at", "..."],
  "hidden_properties": ["prop_<ulid>"],
  "sort": [{ "property_id": "_modified_at", "direction": "descending" }],
  "filter": { "match": "all | any", "rules": [{ "property_id": "...", "op": "...", "value": "..." }] },
  "group": { "kind": "structural" },
  "column_widths": { "_title": 240.0 },
  "collapsed_groups": ["<containerULID or option value or _ungrouped>"],
  "card_size": "small | medium | large",
  "show_cover": false,
  "show_banner": true
}
```

- `property_order` replaces the two-array model: ONE ordered list of all column ids (including `_title`, tiers, `_modified_at`) + the `hidden_properties` set. Legacy `visible_properties` decodes once (`property_order = ["_title"] + legacy`, decode-only key per the `vault_id` precedent); unaccounted schema properties append at resolution time. `ReservedPropertyID` gains `title = "_title"`.
- **GroupConfig** is a tagged object (the `RelationTarget` convention): `{"kind":"structural"}` | `{"kind":"property","property_id":"...","order":[...]}` | `{"kind":"flat"}`. Swift cases `.structural` / `.property` / `.flat` (not `.none` — avoids `Optional.none` ambiguity). `group == nil` ⇒ the structural default. Stable group ids: container ULID / option value / `"true"`//`"false"` / `"_ungrouped"`.
- **Sort presets** encode as reserved property ids (the `DefaultSortConfig` vocabulary): Title → `_title`, Created → `_id` ascending (ULID = creation order), Recent → `_modified_at` descending. `PageType.defaultSort` folds into the minted default view's `sort`, keeps decoding, is never written again.
- **Filter operators** (evaluation-layer enum; unknown `op` = rule no-op): number `is / is_not / greater_than / less_than / is_empty / is_not_empty`; checkbox `is`; date / datetime / lastEditedTime `is / on_or_after / on_or_before / is_empty / is_not_empty`; select / status `is / is_not / is_empty / is_not_empty`; multiSelect `contains / does_not_contain / is_empty / is_not_empty`; relation (tier links) `contains / does_not_contain / is_empty / is_not_empty` (the roadmap's "linked to / not linked to"); url `is / contains / is_empty / is_not_empty`; file `is_empty / is_not_empty`.
- **Cover**: `cover: String?` on `PageFrontmatter` (`CodingKeys` addition keeps `modeledKeys` + YAML round-trip safety automatic). **Banner**: `banner: String?` on both container sidecars. Paths are nexus-relative (`.nexus/assets/<entityID>/<file>`), the `FileRef` convention.
- **Assets**: `NexusPaths.assetsDir` → `.nexus//assets//<entityID>//`; `CoverAssetStore` reuses `AttachmentManager`'s copy / collision / size-guard logic with an image accept list.
- **Active view**: `active_views: [containerID: viewID]` on `NexusState` (`state.json`, `decodeIfPresent`, no version bump), runtime-surfaced by an `@Observable ActiveViewStore` on `NexusEnvironment`. Missing entry → first view.
- **No SQLite changes.** Views are sidecar-only.

### View Pipeline

One pure, unit-tested pipeline feeds every renderer: **fetch (manager arrays = manual order) → filter → group → sort within groups → `[ResolvedGroup]`**. Lives in `Detail//ViewPipeline//` (`ViewItem`, `ViewItemSource`, `FilterEvaluator`, `SortComparator`, `GroupResolver`, `ResolvedGroup`, `GroupDropPlanner`) with no SwiftUI imports.

- Runs in-memory off the `@Observable` caches (`pagesByCollection` / `pagesBySet` / `pagesByTypeRoot`) — instant recompute on any property edit (decision 14). `IndexQuery` is not in this path (it lacks a per-Set target and option-order sorting; it remains the surface for pickers and future embedded views).
- Mutations route through existing manager APIs: reorder → `reorderPages(in:fromOffsets:toOffset:)` (collection / set / vault-root overloads), structural drop → `movePage(_:from:to:)`, property drop → `updatePageProperty(...)` (ungrouped bucket writes `nil`).
- Set label chips resolve synchronously via a new `PageSetManager.set(containing: page.url)` URL-prefix helper (frontmatter doesn't carry set membership).
- **Prerequisite fix — the order-clobber race**: `reorderPages` updates `PageContentManager` caches + writes `page_order` via `OrderPersister` (disk read-modify-write), but `PageTypeManager.pageCollectionsByType` keeps a stale copy that the next `updateView` (whole-struct save) writes back. `updateView` converts to disk read-modify-write before any v2 persistence ships — width and collapse writes would otherwise silently undo reorders.

### Table Renderer

- **Layout** (the two-axis `ScrollView` + `pinnedViews` combination is a confirmed, unfixed platform bug): outer `ScrollView(.horizontal)` holding a pane of `frame(width: totalWidth)`; inner `ScrollView(.vertical)` + `LazyVStack(spacing: 0)`; **group headers render as native-style disclosure rows that scroll with content** (chevron + the grouping value's label — the way native Table disclosure rows read; not pinned bands); only the column header is fixed, mounted via `.safeAreaInset(edge: .top)` on the inner scroll view — fixed vertically, pans horizontally in column alignment with zero offset-sync code. **Spike gates** (half-session, before committing): group headers pin correctly beneath the safeAreaInset header; diagonal-trackpad feel across the nested axes; vertical-scroller placement. Designated fallback: two synced ScrollViews via `onScrollGeometryChange` + `ScrollPosition`.
- **Columns**: `TableColumnResolver` (evolves `PropertyColumnBuilder`'s defensive semantics) maps `property_order` + schema → resolved columns + widths. Resize = `DragGesture` on a trailing handle, snapshot-plus-translation with min-width clamp, live width in an `@Observable` store, sidecar commit on `.onEnded`; `pointerStyle(.columnResize)`. Column drag-reorder = `DragGesture` over the header row (insertion index from prefix-sum width math; headers animate live, body snaps on drop).
- **Rows**: **26pt fixed-height** `HStack`s of exact-width cells — the exact default Apple table design, except alternating rows use the subtler quinary fill (`PUI.Fill.field`) instead of Apple's lighter grey. Cells reuse `PropertyCellEditor` / `PropertyCellDisplay` unchanged (display-first + popover editors, commit-on-dismiss; checkbox and status-box stay direct-toggle). Hover = one container-level `onContinuousHover` + row-height math. Rename via context menu; icon click → IconPicker (decision 14). Column headers: drag to re-arrange, right-click → Hide Column (`_title` exempt).
- **Selection + keyboard** (net-new; today's Table has no selection binding): `Set<RowID>` + anchor; plain / ⌘ / ⇧ click via `onModifierKeysChanged` tracking; `.focusable()` container + `onMoveCommand` arrows + `onKeyPress` type-select. Double-click opens via `PageOpenRouter.routeOpen` (the existing first-click-selects, second-click-opens composition: `TapGesture(count: 2)` + `simultaneousGesture` single-tap).
- **Group sections**: header rows carry the disclosure caret, count, drop target, and the container affordances today's Collection//Set rows provide (Open / Edit Title / Edit Icon / Delete with the existing confirmation dialogs) — these migrate to headers, not disappear. Collapse = `if`-gated section content, persisted per decision 12.
- **Must-not-regress checklist** (from the UI audit): double-click routing per `openIn` mode; Title-cell context menus (Edit Title / Edit Icon / Pin / Delete + container dialogs); per-type cell editor behaviors; popover commit semantics; collection-root-only manual drag (Sets non-draggable as items); rename alert; IconPickerSheet; footer ghost-trail crumb; the `.task` context-resolver warm-up; vault detail additionally warms Set page loads.

### Gallery Renderer

- `LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing:, alignment: .top), count: cardSize))` per section; sections per `ResolvedGroup` with the same pinned headers and collapse behavior as the table.
- **Card anatomy**: cover area only when the view's `show_cover` is on (fixed aspect, `scaledToFill` + clipped; empty fill when no cover is set) → header (icon + title) → property zones — chips (select / multiSelect / status / tier relations, + the Set label chip at vault scope), meta (dates / lastEdited / number / checkbox), links (url) — ordered within zones by `property_order`, showing non-hidden properties, **fully interactive** (the table cells' popover editors; assign + remove values on the card). Card heights are deterministic per size. Exact visual treatment lands with Nathan's Figma pass; the zone partition is componentized so visuals slot in.
- Hover = per-card local `@State` (`onHover`), scale + shadow; single click selects, double-click on the title text renames, double-click elsewhere opens via `PageOpenRouter`; right-click = the page context menu; right-click the visible cover area = Set / Change / Remove Cover.
- Chips reuse `PropertyChip` / `ContextChip` / `PropertyCheckbox` / `StatusCheckbox`.

### Drag & Drop

- **Primary stack = the macOS 26 system drag session APIs** (floor-verified, un-gated; native-first per decision 15): `.draggable` sources + `dropDestination(for:isEnabled:action:)` receiving `DropSession`, with **`onDropSessionUpdated` providing continuous hover `location`** to drive the insertion line / gap and group-header highlight; `onDragSessionUpdated` for drag-side state; `dragContainer` + `dragContainerSelection` for native multi-select drags with `dragPreviewsFormation(.stack)` previews; `springLoadingBehavior` for hover-expanding collapsed groups. Payloads are ID-only `Codable + Transferable` structs.
- Table rows use gap / insertion-line style; gallery cards use live reflow. Group headers and section bodies are drop targets; `GroupDropPlanner` resolves intent — same-container reorder (only when sort = Manual), structural move, or property rewrite.
- Edge auto-scroll during drag is verified in the table spike; if the system stack doesn't provide it in a plain `ScrollView`, the hand-rolled `ScrollPosition` nudge loop fills in.
- **Fallback** (only if the system stack can't hit the wanted feel): a pure-`DragGesture` coordinator vendoring the mechanics of `visfitness//reorderable` (MIT, active; frame registry / hysteresis / origin compensation / auto-scroll), with `globulus//swiftui-reorderable-foreach` as the system-DnD swap-pattern reference. The drag layer is isolated behind one coordinator so the stacks are swappable.
- The same upgraded mechanics apply to the settings reorder surfaces (Edit Properties order, select//status option editors) — replacing their current minimal `.draggable(String)` reorder.
- Keep drop targets out of `List` (unfixed macOS bug: `dropDestination` inside `List` never fires).

### Views Dropdown + View Settings

- **Views dropdown**: a window-toolbar button beside the existing ViewSettings slider button (same `primaryAction` capsule + `.glassEffect()` + popover pattern; static button, reactive scope param). ONE popover, fully custom rows on the `ChipDropdownPanel` surface; the right-side type label is its own button toggling an **inline expansion** (type options — Table + Gallery active; Board/List/Cards muted) inside the same panel — no nested popovers (fragile on macOS). System menus can't render this design (NSMenu styling limits) — custom rows are required. View name + icon edit inline on the row (decision 14). Components stage in ComponentLibrary `.detailViews`.
- **View Settings popover** becomes active-view-scoped. Panes: **Edit Properties** (schema-only per decision 11), **Layout** (Display Banner + Card Size + Property Visibility + muted Wrap Text; the existing vault-scoped open-in selector renames to "Open Pages In"), **Sort** (single picker), **Filter** (rule list + match toggle), **Group** (Default / property picker / Remove grouping). `PropertyVisibilityPane` is retired; pane writes go through `updateView` (post-fix).

### Covers + Banners

- Thumbnail pipeline = **Nuke** (`ImagePipeline` + `ImageRequest.ThumbnailOptions`, `LazyImage`): `file://` fast path, downsampled decode, in-flight coalescing, and a cross-launch disk cache of decoded thumbnails — strictly more than a hand-built loader, Swift 6-native (MIT). QuickLook thumbnails are the later upgrade path for non-image covers.
- Add Cover (cards) and Add Banner (container detail header) follow the Add Icon hover-button pattern → `fileImporter([.image])`, wrapping the copy in `startAccessingSecurityScopedResource` (source may sit outside the granted nexus), destination `CoverAssetStore`.

### Dependencies

- **Nuke** (new SPM dependency, MIT) — thumbnail pipeline.
- No other additions: SwiftUIX (not Swift 6, monolith), SwiftUI-Introspect (Table rescue is a trap), AdvancedCollectionTableView (drag bugs) all evaluated and rejected; qusc/SwiftUI-Popover, the NSTrackingArea gist, and the WWDC23 focus-cookbook are pattern references, not dependencies; `visfitness//reorderable` + `globulus//swiftui-reorderable-foreach` are designated fallback patterns, not dependencies.

### Phases (no dates)

0. Schema v2 + GroupConfig + pipeline (pure, tested) + order-clobber fix + ActiveViewStore.
1. Layout spike → custom table, flat (interaction-checklist parity + persisted widths).
2. Sort + Filter panes wired.
3. Grouping (structural defaults, property group-by, collapse persistence, header affordances).
4. Drag (system-stack rows / groups / multi-select; column reorder; settings surfaces).
5. Gallery + covers + banners (Nuke, assets store, Add Cover).
6. Views dropdown + merged Edit Properties + retirements (`DetailRow`, `DetailRowDragPayload`, `PropertyVisibilityPane`, native `Table` bodies).

### Deferred

Board / List / Cards UI; multi-level sort; nested filter groups; page-editor cover banner (MarkdownPM); a "columns = Sets" Board variant; `IndexQuery` `.pageSet` target + option-order SQL (only needed when embedded views arrive); macOS 27's reorder-container family (absent from the 26.5 SDK — re-evaluate when the floor moves).
