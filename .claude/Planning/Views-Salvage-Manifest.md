## Views Salvage Manifest

Inventory of what to REUSE from the abandoned Views implementation when we retry with a native AppKit table (`NSOutlineView`/`NSTableView` via `NSViewRepresentable`). The custom-SwiftUI-table *renderer* failed and is discarded; the *data layer, pipeline, persistence, and most UI logic* are sound and renderer-independent.

- **Failed branch:** `views-FAILED-custom-table` (tip `e3f9c72`) — full git history of the executed plan + reviews.
- **Retrieve any file:** `git show views-FAILED-custom-table:<path>` · cherry-pick commits, or port file-by-file onto a fresh `views-v2` branch.
- **What broke (why this manifest exists):** the design hand-rolled a "1-1 duplicate of native macOS `Table`" in SwiftUI (decision #1), violating its own decision #15 (*native-first, never hand-roll*). Retry wraps the real AppKit control. See `Handoff.md` post-mortem.

---

### Tier 1 — Reuse as-is (pure logic / data / persistence — renderer-independent)

These are SwiftUI-free or model-only and feed ANY renderer. Highest-value salvage.

- **View pipeline** (`Detail/ViewPipeline/`, Foundation-only, fully unit-tested) — the heart of the salvage:
  - `ViewItem.swift`, `ResolvedGroup.swift` (value types; note `ViewItem` was made `Hashable` by id)
  - `FilterEvaluator.swift` (per-type operator matrix, unknown-op no-op, all/any)
  - `SortComparator.swift` — the type is `ViewSortComparator` (renamed to avoid colliding with Foundation's `SortComparator`; **keep the rename**)
  - `GroupResolver.swift` (structural vault/collection, property buckets, flat, collapse, `flattenedItems`)
  - `ViewItemSource.swift` (stamps parent + setLabel from manager caches; uses `ViewItemScope`, renamed from `ViewScope`)
  - `GroupDropPlanner.swift` — the pure drop-intent decision (`.reorder` / `.move` / `.rewriteProperty` / `.none`); renderer-agnostic, just rewire to the native table's drag callbacks
- **SavedView v2 schema** (`Vaults/SavedView.swift`) — `property_order` (+ legacy `visible_properties` decode-only), `hidden_properties`, `column_widths`, `collapsed_groups`, `card_size` (`CardSize` 8/6/4), `show_cover` (default OFF), `show_banner`; `GroupConfig` discriminated (`.structural`/`.property`/`.flat`, lenient decode). + `ReservedPropertyID.title`, `PropertyType.isSortable` (false for `.lastEditedTime`), `PageFrontmatter.cover`, `PageType`/`PageCollection.banner`.
- **`SavedViewMutations.swift`** — toggle semantics (hide/un-hide, `_title` no-op, `_modified_at` hideable, cover excluded) + `scrubDeletedProperty` (clears a deleted property from every view's sort/group/order/hidden/widths).
- **`updateView` disk-clobber fix** (`Vaults/PageTypeManager.swift`) — `updateView`/`mutateViews` read the sidecar FRESH from disk before save (no `await` between read and write → MainActor-serialized, no stale clobber of `page_order`). **Carry this regardless** — it's a real pre-existing bug fix.
- **View CRUD** (`PageTypeManager`) — `addView` ("Untitled View"; gallery mints `.medium`), `duplicateView` (fresh id, all fields), `deleteView` (≥1-view guard → `cannotDeleteLastView`), `renameView` (trims, rejects empty); all via `mutateViews`.
- **Reorder-by-id** (`Content/PageContentManager.swift`) — `reorderPages(in:movingIDs:before:)` + pure `reorderedIDs(current:movingIDs:before:)` (resolves an anchor that is itself a dragged row to the first non-moving id; container-space, filter/bucket-safe).
- **Active-view persistence** — `Detail/ActiveViewStore.swift` (`@Observable`, reads `state.json`), `NexusState.activeViews` + `viewsButtonStyle`, `OrderPersister.setActiveView`/`setViewsButtonStyle`, `NexusEnvironment` injection line.
- **Covers / banners storage** — `NexusPaths.assetsDir(for:in:)`, `Detail/Covers/CoverAssetStore.swift` (`storeSync` synchronous-inside-security-scope copy, collision suffix, 500MB cap, `delete` with assetsDir containment guard), `PageSetManager.set(containing:)`. + the cover write goes via `updatePageFrontmatter` (root field, NOT `updatePageProperty`).
- **`GalleryCardZones.swift`** — pure chips/meta/links zone partition (cover + `_title` excluded, order verbatim + unaccounted-append).
- **Nuke + NukeUI SPM dependency** (pbxproj `XCRemoteSwiftPackageReference`, Package.resolved) — for cover/banner thumbnails. Already resolved on the branch; copy the pbxproj entries.
- **Tests for all the above** (port with their logic): `Detail/ViewPipeline/*Tests` (Filter/Sort/Group/ViewItemSource + `ViewPipelineFixtures`), `Vaults/SavedViewV2Tests`, `GroupConfigV2Tests`, `UpdateViewClobberTests`, `ViewCRUDTests`, `PropertyDeleteScrubTests`, `ViewSettings/SavedViewMutationsTests`, `Detail/CoverAssetStoreTests`, `Content/CoverFieldTests`, `Detail/ActiveViewStoreTests`, `Detail/GalleryCardZonesTests`, and the `ReorderByIDTests` suite (inside `GroupDropPlannerTests.swift`).

### Tier 2 — Reuse with light adaptation (SwiftUI UI, logic sound, not table-coupled)

- **Gallery renderer** (`Detail/Gallery/GalleryView.swift`, `GalleryCard.swift`) — a real SwiftUI `LazyVGrid` (8/6/4). **Nathan's complaint was the TABLE, not the gallery** — this likely survives mostly intact. Caveats: reuses `PropertyCellEditor` for interactive zones; cover area via NukeUI `LazyImage` + `ImageProcessors.Resize`; the page-icon glyph needs an emoji-aware renderer (see Tier-3 note — the fix was only applied to the table's `TitleCell`). `GalleryDropGeometry.swift` (+ tests) = pure grid insertion math, keep.
- **View-Settings panes** (`ViewSettings/SortPane.swift`, `FilterPane.swift`, `GroupPane.swift`, `LayoutPane.swift`, `PropertiesListPane.swift` schema-only edit, `StorageMenuRoot`/`ViewSettingsRoute`/`ViewSettingsPopover` routing) — they write renderer-agnostic `SavedView` config and resolve the active view via `ActiveViewStore` (NOT `views.first`). No dependency on the custom table. Reuse the logic; restyle freely. + `FilterGroupPaneTests`, `SortPersistenceTests`.
- **Views dropdown** (`Detail/ViewTabs/ViewsDropdownButton.swift`, `ViewsPanel.swift`, `ViewsPanelRow.swift`) — multi-view switch/CRUD UI, renderer-agnostic. Note the unfinished feedback: **Views must read as a clearly separate toolbar pill** (pill-sizing fix was in progress), and the dropdown styling per Figma.
- **Covers/banners UI** (`Detail/Covers/CoverPicker.swift`, `ContainerBannerView.swift`) — `fileImporter` + the security-scope sequence (copy synchronous inside scope, async write after) + `pendingError` surfacing. Note unfinished feedback: **Add Banner must match the page "Add Icon" affordance** (`plus.app` + `.tertiary` ghost, hover-revealed — the fix was applied on the branch tip, port it).
- **`PropertyCellEditor` live-options fix** (`Detail/Columns/PropertyCellEditor.swift`) — multiSelect re-seeds on `.onChange(of: definition.selectOptions)` (was `.onAppear`-only). Partial fix for the "new options need restart" bug; the deeper observation-scope cause is still open (needs a live repro).
- **Settings-editor insertion line** (`Properties/Editor/OptionRowInsertionLine.swift` + `SelectOptionsEditor`/`StatusGroupsEditor` adoption) — independent drag-feedback polish, fully reusable.
- **`TableColumnResolver.swift`** — the *column-resolution logic* (which columns from `property_order` + schema, hidden respected, cover never a column, Title structurally guaranteed, per-type SF Symbol) is renderer-agnostic and reusable to populate `NSTableColumn`s. **Discard the `ColumnLayout` geometry store** (custom-table-specific). Adapt the resolver's output to the native table's column model.

### Tier 3 — DISCARD (the failed custom-SwiftUI-table renderer + its harness)

The native AppKit table replaces ALL of these — it provides their behavior for free.

- `Detail/Table/CustomTableView.swift`, `TableHeaderRow.swift`, `TableGroupRow.swift`, `TableRowView.swift` (the renderer itself)
- `Detail/Table/ColumnLayout.swift`, `ColumnDragController.swift` (column geometry/drag — NSTableView does columns natively)
- `Detail/Table/TableSelectionModel.swift` (selection/keyboard — NSTableView does this natively)
- `Detail/Table/RowDragCoordinator.swift`, `RowDragGeometry.swift`, `ViewRowDragPayload.swift` (the hand-rolled drag engine + live-preview geometry — NSTableView/NSOutlineView reorder is native)
- `Detail/Table/PageMetaPin.swift` (pin helper relocated from `DetailRow`; on `main` the pin helper still lives in `DetailRow.swift` — no need to salvage)
- `ComponentLibrary/Galleries/TableLayoutSpike.swift`, `Detail/ViewTabs/ViewsDropdownRowGallery.swift` (component-library staging)
- The **detail-view rewrites** (`Detail/PageTypeDetailView.swift`, `PageCollectionDetailView.swift`) were rewritten to host `CustomTableView` + the `RowTarget` bridge — discard those rewrites; the native renderer re-hosts (keep the alert/dialog/`.task` warm-ups + footer from `main`'s versions).
- Table-specific tests: `ColumnDragMathTests`, `RowDragGeometryTests`, `TableColumnResolverTests`, `TableSelectionModelTests` (re-derive against the native table where still relevant).
- On `main`, the native `Table` / `DetailRow` / `PropertyColumnBuilder` were NEVER removed (the retirements were branch-only) — so nothing to restore there.

### Retry sequencing (suggested)

1. **Brainstorm the native approach with Nathan** — `NSOutlineView` (gives disclosure groups) vs `NSTableView` + row-groups; how the pipeline feeds it; screenshot the *rendered look* before building outward.
2. Branch `views-v2` off `main`. Port **Tier 1** wholesale (schema → pipeline → persistence → covers/CRUD/active-view) with its tests — this is most of the green-test value and has no renderer risk.
3. Build the `NSViewRepresentable` table fed by `GroupResolver`'s `[ResolvedGroup]`; map `TableColumnResolver`'s columns to `NSTableColumn`s; wire native selection/reorder to `reorderedIDs` + `GroupDropPlanner`.
4. Re-host the detail views; layer in **Tier 2** (gallery, panes, dropdown, covers UI) — restyling the toolbar pill + Add Banner per the noted feedback.
