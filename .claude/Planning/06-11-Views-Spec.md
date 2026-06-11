## Views — Pre-Design Findings (Spec Feed)

**Status:** not a ratified design. This is the findings ledger for the Views feature cluster — the next focus after Sets — consolidating what the codebase already establishes, what the roadmap scopes, and what the Sets design pass surfaced. The Views design pass starts from this doc.

### What exists in code today

- `SavedView` (`Vaults/SavedView.swift`): `id` (`view_<ULID>`), `name`, `icon`, `type` (`ViewType`, only `.table` live), `visibleProperties` / `hiddenProperties` (ordered property-ID columns), plus three **reserved unconsumed stubs**: `sort: [SortCriterion]?`, `filter: FilterGroup?`, `group: GroupConfig?`.
- `GroupConfig` is property-only — `propertyID: String` + optional `order`. See requirements below; this shape must change before first consumption.
- `views: [SavedView]` lives independently on both `PageType` and `PageCollection` sidecars (locked: Collection views are independent of the parent Type's). A default Table view is minted on load when `views` is empty.
- `PageType.defaultSort` (`DefaultSortConfig?`) carries per-vault sort persistence; column-header click-to-sort exists in detail tables.
- Manual ordering is parent-sidecar-resident (`collection_order` / `set_order` / `page_order` per container) via `OrderResolver` + `OrderPersister`; Type detail tables are **display-only** for row order (mirror the sidebar) because macOS `Table` can't combine collapsible grouping with reliable nested reorder.
- The Sort / Filter / Group panes in the View Settings popover are present but muted; multi-saved-view tabs are not built.
- `IndexQuery` already supports Notion-style filter + sort against targets `.pageType(id)` / `.pageCollection(id)` (JSON-extract on the `properties` column).

### Roadmap scope (carried from Framework)

Board / List / Cards / Gallery renderers over the per-container `SavedView` storage; multi-saved-view tabs beneath the detail title; full per-view config — order, sort, Group By, column selection; tier-link sort + filter (`linked to` / `not linked to` operators); Board = kanban (cards grouped by a property's options, editing via card UI); the deferred per-view reorder engine; FTS5 table wiring lands in the same cluster (search UI later).

### Requirements surfaced by the Sets design

- **`GroupConfig` becomes a discriminated value: property-or-container.** Structural grouping (by Collection at Vault level, by Set at Collection level) is not a property. The stub is unconsumed, so reshaping it now is free; retrofitting after first consumption is a migration.
- **Structural grouping is the default.** Vault views default to group-by-Collection with each Collection's Sets nested inside its disclosure; Collection views default to group-by-Set. Container-root pages render as an ungrouped band.
- **Property grouping replaces and flattens** structural grouping; sort applies within each disclosure group either way.
- **The reorder engine writes manual order to the grouped row's owning container sidecar** (a Set's rows → that Set's `page_order`), not to a view-level list.
- **Board stays property-driven in the base design.** A "columns = Sets" Board variant is a clean later option — dragging a card between Set columns is a free in-Vault move (no schema, no strip) — but is not required.
- **Container grouping must live in `SavedView`, not view-local state**, because the Contexts block editor's embedded-collection-views render the same `SavedView` machinery inline; whatever a Collection view can express, an embedded view must reproduce.
- **Result/row identification uses `EntityContainer`** (Vault › Collection › Set), already extended by Sets — grouped views, search results, and embedded views compose breadcrumbs from one source.

### Platform notes (verified against current Apple docs)

Hierarchical `Table(_:children:)` + `DisclosureTableRow` exist on macOS; the standing limitation is combining collapsible grouping with reliable nested reorder (the display-only fallback stands until the reorder engine solves it). `dropDestination(for:)` works on List and Table rows — drag-into-group is platform-supported. `List(_:children:)` / `OutlineGroup` handle arbitrary-depth disclosure natively.
