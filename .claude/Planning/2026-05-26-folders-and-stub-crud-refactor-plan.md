### Plan — Page Folders (Three-Layer Pages Side)

#### Context

Pommora's Pages side is locked at two organizational levels — Page Type (Vault) → Page Collection — and two-layer nesting becomes practical-limiting for research-style hierarchies (Research > Topic > Specific). This plan adds a third tier, **Folder**, that lives strictly inside a Page Collection and contains Pages only. **It also refactors every existing "New X" creation flow** (PageType, PageCollection, Page, ItemType, ItemCollection, Item) to drop the modal-sheet pattern in favor of stub-and-inline-rename — Folder creation inherits that uniform pattern rather than introducing yet another sheet.

Bounded depth: **PageType → PageCollection → Folder → Page** is the three-layer maximum. No nested Folders. No nested Collections inside Folders. Only "New Page" exists as a child-creating action inside a Folder. Items side and Agenda side are untouched. Pages may continue to live at PageType root or PageCollection root alongside Folders (mirrors how Pages already live at PageType root alongside Collections).

Folders are sidebar-routable like Collections — selecting a Folder opens a list-view detail surface that mirrors `PageCollectionDetailView`. Folders are pinnable but not recorded in Recents (mirrors Collection precedent: `RecentsManager.recordableKinds = {.page, .item, .agenda}` only). View visibility, sort, filter, and group are handled per-Folder through `views: [SavedView]` — the same uniform mechanism Page Types and Page Collections use today, which means the upcoming v0.3.1.x Sort/Filter/Group panes light up on Folders automatically.

Folders have **customizable per-Folder icons** (decided this session) — a deliberate divergence from Collections, which use a hardcoded `folder` symbol. The Folder icon-picker reuses the same SymbolPicker infrastructure that Page Types and Topics use today.

**View-state independence (locked decision, this session):** A Folder carries its own `views: [SavedView]` array that is independent of its parent Collection's `views` — the same independence relationship Collections already have with their parent Types (per the locked comment at [PageCollection.swift:21–25](Pommora/Pommora/Vaults/PageCollection.swift#L21-L25)). Visibility (visible/hidden property columns), sort, filter, group, and layout are all stored inside `views[0]` and edited per-Folder through the View Settings popover. The Folder's property *schema* still inherits from the grandparent PageType (last session's decision); only the view-level dials are per-Folder. A fresh Folder mints a default Table view via `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` so it has a sane starting point, then evolves independently.

Execution follows quirk #8 (stub-and-progressively-replace): each phase ships green standalone, later phases swap stubs for real surfaces in place.

#### On-Disk Shape

```
<nexus>/
  <PageType>/
    _pagetype.json
    <PageCollection>/
      _pagecollection.json
      Page-at-collection-root.md
      <Folder>/                    ← NEW: sub-folder with _folder.json sidecar
        _folder.json
        Page-in-folder.md
        Page-2-in-folder.md
      <Folder-2>/
        _folder.json
        ...
    Page-at-type-root.md
```

**Sidecar discriminates kind** (existing pattern). A sub-folder inside a Collection without `_folder.json` continues to be Obsidian-style adoption — its `.md` files roll up into the parent Collection (existing behavior at `PageContentManager.swift:101–104` preserved). Drop a `_folder.json` in to promote it.

Constants land in [NexusPaths.swift](Pommora/Pommora/AtomicIO/NexusPaths.swift) alongside the six existing per-kind sidecar filenames ([NexusPaths.swift:10–20](Pommora/Pommora/AtomicIO/NexusPaths.swift#L10-L20)):

```swift
/// `_folder.json` — Folder sub-sub-folder sidecar (third-tier on Pages side).
static let folderSidecarFilename = "_folder.json"
```

Path helpers to add (following the existing `pageCollectionFolderURL` / `pageCollectionMetadataURL` pattern at [NexusPaths.swift:248–284](Pommora/Pommora/AtomicIO/NexusPaths.swift#L248-L284)):

```swift
static func folderFolderURL(
    in nexusRoot: URL,
    typeFolderName: String,
    collectionFolderName: String,
    folderFolderName: String
) -> URL

static func folderMetadataURL(
    in nexusRoot: URL,
    typeFolderName: String,
    collectionFolderName: String,
    folderFolderName: String
) -> URL
```

#### Folder Model

New file: [Pommora/Pommora/Vaults/Folder.swift](Pommora/Pommora/Vaults/Folder.swift) — mirror of [PageCollection.swift](Pommora/Pommora/Vaults/PageCollection.swift) with `collectionID` added and `icon` added.

```swift
struct Folder: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String                  // ULID from _folder.json
    var typeID: String              // ULID of grandparent PageType (FK convenience)
    var collectionID: String        // ULID of parent PageCollection
    var title: String               // derived from folder name (not persisted)
    var folderURL: URL              // runtime only
    var icon: String?               // SF Symbol — customizable per-Folder
    var modifiedAt: Date
    var schemaVersion: Int          // 1 at v1; pre-existing sidecars decode as 0
    var pageOrder: [String]?        // mirror PageCollection.pageOrder
    var views: [SavedView] = []     // mirror PageCollection.views
}
```

JSON sidecar keys: `id`, `type_id`, `collection_id`, `icon`, `modified_at`, `schema_version`, `page_order`, `views` (snake_case for parity with existing sidecars). Implement `init(from:)` / `encode(to:)` / `static func load(from:) throws` / `func save(to:) throws` following the [PageCollection.swift](Pommora/Pommora/Vaults/PageCollection.swift) pattern exactly.

**Fresh-Folder view seed (locked decision, this session):** `createFolder(in:title:)` mints a single default Table view via `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` — cold start, identical to how Collections start. The Folder does NOT copy its parent Collection's current view state; users configure each Folder independently from a clean default.

#### SQLite Schema + Migration

Add to [IndexSchema.swift](Pommora/Pommora/Index/IndexSchema.swift) as a new GRDB migration step using GRDB v7's builder syntax (additive only — never mutate prior migration steps). Schema-only migrations use `foreignKeyChecks: .immediate` per GRDB best practice (skips the temporary FK-disable cycle and runs faster):

```swift
migrator.registerMigration("v0.3.2.0 Folders tier", foreignKeyChecks: .immediate) { db in
    try db.create(table: "folders") { t in
        t.column("id", .text).primaryKey()
        t.column("page_collection_id", .text)
            .notNull()
            .references("page_collections", onDelete: .cascade)
        t.column("page_type_id", .text)
            .notNull()
            .references("page_types", onDelete: .cascade)
        t.column("title", .text).notNull()
        t.column("icon", .text)
        t.column("modified_at", .datetime).notNull()
        t.column("schema_version", .integer).defaults(to: 1)
    }
    try db.create(index: "idx_folders_page_collection_id",
                  on: "folders", columns: ["page_collection_id"])
    try db.create(index: "idx_folders_page_type_id",
                  on: "folders", columns: ["page_type_id"])

    try db.alter(table: "pages") { t in
        t.add(column: "page_folder_id", .text)
            .references("folders", onDelete: .setNull)
    }
    try db.create(index: "idx_pages_page_folder_id",
                  on: "pages", columns: ["page_folder_id"])
}
```

A Page in a Folder fills `page_type_id` + `page_collection_id` (Folder's parent) + `page_folder_id`. A Page at Collection root fills `page_type_id` + `page_collection_id`, `page_folder_id` null. A Page at Type root fills `page_type_id` only.

Extend [IndexQuery.swift](Pommora/Pommora/Index/IndexQuery.swift) with a `.folder(folderID)` scope returning `SELECT id, title FROM pages WHERE page_folder_id = ?`.

**Repopulation strategy.** [IndexBuilder.populate](Pommora/Pommora/Index/IndexBuilder.swift#L134) uses a `DELETE FROM ...` wipe followed by full re-insert ([IndexBuilder.swift:403–416](Pommora/Pommora/Index/IndexBuilder.swift#L403-L416)) — *"the DB is a regeneratable index (no user data), a full wipe + repopulate is safe."* This means the migration's new `folders` table simply gets populated on the next IndexBuilder run with no special "post-migration backfill" logic required. The migration adds empty structure; IndexBuilder's existing wipe-and-rebuild fills it.

#### Index Snapshots + IndexBuilder

[IndexBuilder.swift](Pommora/Pommora/Index/IndexBuilder.swift) uses a two-phase strategy: a `@MainActor` filesystem walk that produces a `Sendable` `NexusSnapshot`, then a `@Sendable` GRDB write closure that wipes and re-inserts. Extend the private snapshot structs (they must remain `Sendable` to cross the actor boundary):

```swift
private struct PageCollectionSnapshot: Sendable {
    let id: String
    let title: String
    let modifiedAt: Date
    let schemaVersion: Int
    let folders: [FolderSnapshot]    // NEW
    let pages: [PageSnapshot]        // existing — pages at Collection root
}
private struct FolderSnapshot: Sendable {
    let id: String
    let title: String
    let pageCollectionID: String
    let pageTypeID: String
    let icon: String?
    let modifiedAt: Date
    let schemaVersion: Int
    let pages: [PageSnapshot]
}
```

`PageSnapshot` gains an additional `folderID: String?` field (nullable). In `collectPageTypes(from:)` ([IndexBuilder.swift:166–209](Pommora/Pommora/Index/IndexBuilder.swift#L166-L209)), after walking each Collection's sub-folders for `_pagecollection.json`, walk that Collection's sub-folders for `_folder.json` and emit `FolderSnapshot`s. The existing `collectPagesInFolder` helper ([IndexBuilder.swift:211–232](Pommora/Pommora/Index/IndexBuilder.swift#L211-L232)) accepts a nullable `collectionID` — extend it with a nullable `folderID` too and thread the right FK trio (`pageTypeID`, `collectionID`, `folderID`) into `PageSnapshot`.

`clearAllTables` ([IndexBuilder.swift:403–416](Pommora/Pommora/Index/IndexBuilder.swift#L403-L416)) gains `DELETE FROM folders` (ordered correctly relative to `DELETE FROM pages` so the FK doesn't object — `pages` is already deleted before `folders` would need to be cleared; the strict dependency order is `pages` → `folders` → `page_collections` → `page_types`). `insertPageTypes` ([IndexBuilder.swift:418–444](Pommora/Pommora/Index/IndexBuilder.swift#L418-L444)) gains a nested loop inserting Folders after their parent Collection, then Pages inside each Folder. `insertPage` ([IndexBuilder.swift:446–454](Pommora/Pommora/Index/IndexBuilder.swift#L446-L454)) gains `page_folder_id` in its INSERT.

#### Managers

Manager strategy: **add Folders as a third indexing dimension on `PageTypeManager`**, not a separate `FolderManager`. This mirrors how `PageTypeManager.pageCollectionsByType: [String: [PageCollection]]` keys Collections by their parent Type ID.

Add to [PageTypeManager.swift](Pommora/Pommora/Vaults/PageTypeManager.swift):

```swift
private(set) var foldersByCollection: [String: [Folder]] = [:]
func folders(in collection: PageCollection) -> [Folder]
```

Extend `loadAll` (lines 31–120) to also walk each Collection's sub-folders for `_folder.json`, populate `foldersByCollection`, and defensively upsert each Folder into SQLite per quirk #15. Add CRUD: `createFolder(in:title:)`, `renameFolder(_:to:)`, `deleteFolder(_:)`, `reorderFolders(in:_:)`. Each mirrors the existing `createPageCollection` / `renamePageCollection` shape line-for-line.

Default-view migration extends: if a loaded Folder has `views.isEmpty`, mint `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` (same as Collection migration at lines 63–68).

Add to [PageContentManager.swift](Pommora/Pommora/Pages/PageContentManager.swift):

```swift
private(set) var pagesByFolder: [String: [PageMeta]] = [:]
func pages(in folder: Folder) -> [PageMeta]
```

Extend the load walk so Pages with a `_folder.json` parent sub-folder land in `pagesByFolder`, not `pagesByCollection`. `resolveParent(for:)` (lines 70–86) gains a third lookup layer.

Add to [PageContentManager+CRUD.swift](Pommora/Pommora/Pages/PageContentManager+CRUD.swift): a `folder: Folder?` parameter on the page-creation path (default `nil`). When set, the on-disk write target is the Folder's `folderURL`, and the SQLite upsert fills `page_folder_id` + `page_collection_id` + `page_type_id`.

#### Sidebar Tree

`SelectionTag` ([SidebarSelection.swift:176](Pommora/Pommora/Sidebar/SidebarSelection.swift#L176)) gains `case folder(String)`. `SidebarSelection` (line 1) gains `case folder(Folder)`. Both `matches(_:)` and the bidirectional `init?(_:)` extend with the new case.

`VaultDisclosureItem` in [PageTypeRow.swift:10–20](Pommora/Pommora/Sidebar/PageTypeRow.swift#L10-L20) is fine as-is — its children remain `.collection(PageCollection)` + `.page(PageMeta)` (Pages at PageType root). It's the **Collection row's children** that gain a Folder case.

Replace [PageCollectionRow.swift:20–42](Pommora/Pommora/Sidebar/PageCollectionRow.swift#L20-L42) — its `ForEach` over `contentManager.pages(in: collection)` becomes a `ForEach` over a new local enum:

```swift
enum CollectionChildItem: Identifiable {
    case folder(Folder)
    case page(PageMeta)
    var id: String { ... }
}
```

The items array combines `pageTypeManager.folders(in: collection).map(.folder)` + `contentManager.pagesAtCollectionRoot(in: collection).map(.page)`. Folders render first, root Pages after. One `ForEach`, one `.onMove` — quirk #9 (no row-shape asymmetry inside a single Section/ForEach) is preserved because both branches yield disclosure-style rows: Folders are disclosure parents, but root Pages render with the same flat `SelectableRow` they do today inside Collections. The disclosure-vs-flat asymmetry already exists at the PageTypeRow level today; we're not introducing a new asymmetry, we're propagating the existing pattern down one level.

New file: [Pommora/Pommora/Sidebar/FolderRow.swift](Pommora/Pommora/Sidebar/FolderRow.swift) — disclosure parent wrapping `PageRow` children, structurally identical to [PageCollectionRow.swift](Pommora/Pommora/Sidebar/PageCollectionRow.swift). It uses `SelectionChrome(isFlat: false)` (disclosure indent) and the same inline-rename `RenameableRow` pattern. Context menu: `New Page (in This Folder)` + `Rename` + `Delete` — no `New Collection`, no `New Folder` (three-layer cap enforced at UI).

**Additional [PageCollection.swift](Pommora/Pommora/Vaults/PageCollection.swift) field addition** (mirroring how [PageType.swift](Pommora/Pommora/Vaults/PageType.swift) already carries both `collectionOrder` and `pageOrder` for two coexisting child kinds): add `folderOrder: [String]?` to hold the persisted display order of Folders inside this Collection, alongside the existing `pageOrder: [String]?` which now applies specifically to Pages-at-Collection-root. JSON key: `folder_order` (snake_case) + the existing `page_order`. Both nil until the user reorders. Drag-reorder is intra-group only — Folders reorder among Folders, Pages among Pages — never mixed (mirrors the PageType-level pattern).

`PageParent` (the enum carried by `PageRow` for context-aware breadcrumbs and reorder routing) gains `case folder(Folder, collection: PageCollection, vault: PageType)`. Every site that switches on `PageParent` extends with the new case — these are linear, mechanical additions.

#### Detail View

New file: [Pommora/Pommora/Detail/FolderDetailView.swift](Pommora/Pommora/Detail/FolderDetailView.swift) — structural mirror of [PageCollectionDetailView.swift](Pommora/Pommora/Detail/PageCollectionDetailView.swift). Header shows Folder icon + title. Body iterates `contentManager.pages(in: folder)`. A "New Page" trigger at the end of the list calls the F.0 `CreateWithInlineEdit` coordinator — adds a stub `"New Page"` row to the list and focuses its title field; no sheet. Session-local drag-reorder via `.onMove` calls `contentManager.reorderPages(in: folder, ...)`. View Settings popover binds to a new `ViewSettingsScope.folder(Folder)` case so visibility / sort / filter / group all attach via the existing pane infrastructure.

[ContentView.swift](Pommora/Pommora/ContentView.swift) detail dispatch (around line 307) gains:

```swift
case .folder(let f):
    FolderDetailView(folder: f, ...)
```

**Critical** per quirk #16: every `@Environment(X.self)` declared on `FolderDetailView` MUST also be in `ContentView.detail`'s optional-unwrap chain (~line 237) AND the subsequent `.environment(...)` injection chain. Missing env asserts as `EXC_BREAKPOINT` on first selection.

#### View Settings Popover

Extend `ViewSettingsScope` in [StorageMenuRoot.swift](Pommora/Pommora/ViewSettings/StorageMenuRoot.swift) with `.folder(Folder)`. The locked Collection-scope behavior at lines 137–142 ("display-only header — Collections rename via the sidebar context menu") needs reconsideration for Folders since Folders have customizable icons:

- `isTypeScope` returns `false` for Folder (same as Collection)
- BUT the `iconAffordance` becomes tappable for `.folder` (opens SymbolPicker) — divergence from Collection
- `titleAffordance` remains display-only for Folder (rename still happens via sidebar context menu, mirroring Collection)

The Property Visibility / Sort / Filter / Group panes already bind to `views[0]` of whatever scope they're handed — no change needed inside the panes, just thread the Folder's `views` array through.

#### Navigation: Pinned, Recents, Back/Forward

[EntityStateRef.swift](Pommora/Pommora/NavDropdown/EntityStateRef.swift) gains `case folder` in its `Kind` enum and a `.folder(let f)` branch in `init?(sidebarSelection:)`. Folders are pinnable.

`RecentsManager.recordableKinds` ([RecentsManager.swift](Pommora/Pommora/NavDropdown/RecentsManager.swift)) **stays at `{.page, .item, .agenda}`** — Folders are organizational, not destinations. Back/Forward already only walks the recents list, so Folders don't appear there; routing through a Folder to reach a Page still records the Page (last destination), which is the existing behavior for Collections.

`SidebarLookupBundle` (the reverse-resolver used by Pinned restore on launch) needs `cm.folder(byId:)` lookup added.

#### CRUD Triggers (No Popups — System-Wide Refactor)

**Decision locked this session: every "New X" CRUD trigger across Pommora switches to stub-and-inline-rename.** No modal sheets. This applies to:

- New PageType (Vault)
- New PageCollection
- New Folder (the new tier)
- New Page (at PageType root, PageCollection root, OR inside a Folder)
- New ItemType
- New ItemCollection (Set)
- New Item

The shared pattern, regardless of trigger location (sidebar context menu, detail-view footer "+" button, keyboard shortcut, or detail-view list end):

1. Manager method (`createPageType`, `createPageCollection`, `createFolder`, `createPage`, `createItemType`, `createItemCollection`, `createItem`) is called with a **default title** generated by `DefaultTitleResolver` — `"New <Label>"` if no sibling carries that title, else `"New <Label> 2"`, `"New <Label> 3"`, etc. Integer disambiguator only, no timestamps. The `<Label>` is pulled from `SettingsLabels` (e.g., "Folder" / "Vault" / "Set").
2. Manager creates the entity on disk + in memory + in SQLite atomically (existing CRUD path, returning the new entity's ID).
3. View layer sets `editingID = newID` on the corresponding row binding, transitioning the row to inline-rename mode (`RenameableRow` with `@FocusState` focused).
4. The newly-created row also becomes the selected sidebar entity AND scrolls into view, so the user immediately sees what they made and types the real name.
5. Enter commits the rename through the manager's existing rename path (`renamePageType` / `renamePageCollection` / etc.). Esc reverts to the stub default title but leaves the entity created (user can delete via the row's context menu if they regret it).

**Shared mechanism:** new file [Pommora/Pommora/CRUD/CreateWithInlineEdit.swift](Pommora/Pommora/CRUD/CreateWithInlineEdit.swift) — a thin coordinator type that orchestrates the manager-call → editingID-binding-flip → focus hand-off sequence. Each row type (PageTypeRow, PageCollectionRow, FolderRow, PageRow, ItemTypeRow, ItemCollectionRow) exposes a single `@Binding var editingID: String?` that the coordinator writes to.

**Files to delete:**
- `Pommora/Pommora/Sidebar/Sheets/NewPageCollectionSheet.swift`
- `Pommora/Pommora/Sidebar/Sheets/NewPageSheet.swift`
- `Pommora/Pommora/Sidebar/Sheets/NewItemCollectionSheet.swift`
- `Pommora/Pommora/Sidebar/Sheets/NewItemSheet.swift`
- Any analogous `NewPageTypeSheet.swift` / `NewItemTypeSheet.swift` if present
- All corresponding `case newXxx(...)` entries in `SidebarSheet` and routing in `SidebarView.swift`

**Detail-view footer "+" buttons** (e.g., "New Page" button at [PageCollectionDetailView.swift:159](Pommora/Pommora/Detail/PageCollectionDetailView.swift#L159), plus the analogous Item-Collection footer button) call the same `CreateWithInlineEdit` coordinator. The new stub row appears at the end of the detail-view list (or wherever the persisted order array places it after the default-title disambiguator runs) AND in the sidebar tree simultaneously, with the title text field focused for typing. Same exact UX whether you triggered it from the sidebar or the detail view's footer.

**Validators move from sheet-driven to commit-driven.** Today, sheets validate before allowing submit (rejecting collisions in their TextField). With stub-and-edit, the stub is created with a guaranteed-unique default title; validation runs when the user hits Enter to commit the rename — same validators (`PageCollectionValidator`, `FolderValidator`, etc.), just invoked from the rename path instead of the create path. On rename collision, the inline editor surfaces the existing error treatment (red underline + tooltip) and refuses to commit; the stub-title fallback remains.

#### "Move to" Context-Menu Submenu (No Popups)

**"Move to ▸" uses a nested context-menu submenu, not a sheet.** Eliminating any modal page-move picker — same anti-popup spirit as the create flows. Right-clicking a Page row in any container surfaces:

```
Move to ▸
    ┌──────────────────────────────────┐
    │ ◇ Research            (current)  │  ← current location, disabled
    │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
    │ Research                     ▸    │
    │     Top of Vault                  │
    │     Sources                  ▸    │
    │         Top of Collection         │
    │         2026-Q2                   │
    │         2026-Q3                   │
    │     Books                    ▸    │
    │         Top of Collection         │
    │ Lifelogging                  ▸    │
    │     Top of Vault                  │
    │     Daily                    ▸    │
    │         Top of Collection         │
    │         …                         │
    └──────────────────────────────────┘
```

SwiftUI `Menu { ... }` inside a `.contextMenu { ... }` block produces nested cascades natively on macOS. Each leaf calls `pageContentManager.movePage(_:to:)`. The current parent is rendered as a disabled-and-marked row at the top (orientation cue). Long destinations are paginated by macOS automatically when the menu height exceeds the screen.

Trigger sites:
- Right-click on Collection row → "New Folder" + existing "New Page (in This Collection)" — both stub-and-edit, no sheets
- Right-click on Folder row → "New Page (in This Folder)" only (no nested Folder, no Collection — three-layer cap enforced)
- Right-click on Page row (in any container) → existing items + "Move to ▸" submenu (always available; greys out if there are no valid destinations beyond the current parent)
- Detail-view footer "+" buttons (Collection's "New Page", Item Collection's "New Item", Folder's "New Page") — all stub-and-edit
- Future: keyboard shortcuts (⌘N creates a Page in the currently-selected container — Type root, Collection root, or Folder) — same stub-and-edit path

**"Move to…" uses a nested context-menu submenu, not a sheet.** Decision locked this session — eliminating the modal `MovePageSheet` in favor of an in-place SwiftUI `Menu` cascade. Right-clicking a Page row in any container surfaces:

```
Move to ▸
    ┌──────────────────────────────────┐
    │ ◇ Research            (current)  │  ← current location, disabled
    │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
    │ Research                     ▸    │
    │     Top of Vault                  │
    │     Sources                  ▸    │
    │         Top of Collection         │
    │         2026-Q2                   │
    │         2026-Q3                   │
    │     Books                    ▸    │
    │         Top of Collection         │
    │ Lifelogging                  ▸    │
    │     Top of Vault                  │
    │     Daily                    ▸    │
    │         Top of Collection         │
    │         …                         │
    └──────────────────────────────────┘
```

SwiftUI `Menu { ... }` inside a `.contextMenu { ... }` block produces nested cascades natively on macOS — no sheet, no modal. Each leaf calls the same `pageContentManager.movePage(_:to:)` backend. The current parent is rendered as a disabled-and-marked row at the top of the top-level menu (orientation cue: "you're here now"). Long destinations are paginated by macOS automatically when the menu height exceeds the screen.

Trigger sites:
- Right-click on Collection row → "New Folder" + existing "New Page (in This Collection)"
- Right-click on Folder row → "New Page (in This Folder)" only (no nested Folder, no Collection — three-layer cap enforced)
- Right-click on Page row (in any container) → existing items + "Move to ▸" submenu (always available; greys out if there are no valid destinations beyond the current parent)
- Collection detail footer → existing "New Page" button kept; "New Folder" surfaces only via right-click on the Collection row (keeps the detail view focused on its primary action)

#### Settings + Labels

[SettingsLabels.swift](Pommora/Pommora/Settings/SettingsLabels.swift) currently holds seven LabelPair fields ([SettingsLabels.swift:3–22](Pommora/Pommora/Settings/SettingsLabels.swift#L3-L22)): `pageType`, `pageCollection`, `itemType`, `itemCollection`, `project`, `agendaTask`, `agendaEvent`. Add an eighth:

```swift
var folder: LabelPair  // defaults "Folder" / "Folders"
```

CodingKey: `case folder = "folder"`. The struct's `defaults()` static (line 24) gains `folder: LabelPair(singular: "Folder", plural: "Folders")`. SettingsLabels decode is explicit via the struct's auto-synthesized init (no custom decoder today) — adding a new field that's not in legacy `settings.json` would crash decode. Add a custom `init(from:)` that calls `decodeIfPresent` for `folder` with the default fallback, matching the defensive pattern used in [SidebarSectionLabels.init(from:)](Pommora/Pommora/Settings/SettingsLabels.swift#L76-L85). Every sidebar / context-menu / detail-view string that reads `settingsManager.settings.labels.pageCollection.singular` in a Folder context reads `.folder.singular` instead. `DefaultTitleResolver` also consumes these labels — "New \(labels.folder.singular)" → "New Folder" by default, automatically picking up renames if the user customizes the label.

[SidebarSectionLabels](Pommora/Pommora/Settings/SettingsLabels.swift#L44-L85) is untouched — Folders are nested under Collections, not a top-level sidebar section, so the section-label set (`spaces` / `topics` / `pages` / `items`) doesn't grow.

#### Cross-Container Move (Context-Menu Only)

**Sidebar drag is for same-zone reorder only** — never used for cross-container moves. Decision locked this session.

Same-zone reorder zones in [DetailRowDragPayload](Pommora/Pommora/Sidebar/DetailRowDragPayload.swift) (or wherever the `.zone` enum lives):

- `.vaultCollection` — Collections reorder among Collections inside a PageType (existing)
- `.vaultFolder` — **NEW** — Folders reorder among Folders inside a PageCollection
- `.vaultPage` — Pages reorder among Pages inside their direct parent (Type root, Collection root, or Folder)

Any cross-zone drop is rejected. No drag-onto-row container moves. Drag is purely for ordering siblings, never for relocation.

**Cross-container moves go through the nested "Move to ▸" context-menu submenu** described in the CRUD Triggers section above. No modal sheet. Available on Page rows in every Pages-side container — Vault (PageType root), Collection (PageCollection root), and Folder.

**Backend move operation:** `PageContentManager.movePage(_ page: PageMeta, to destination: PageMoveDestination)` where `PageMoveDestination` is an enum of `.typeRoot(PageType)`, `.collectionRoot(PageCollection)`, `.folder(Folder)`. The operation: (1) atomic rename of the `.md` file from old location to new location on disk; (2) SQLite update of `page_type_id` / `page_collection_id` / `page_folder_id` to reflect new parentage; (3) in-memory tree update (`pagesByCollection` / `pagesByFolder` / `pagesByTypeRoot` rebalanced); (4) ID stays unchanged so wikilinks and relations resolve as before. Failures are surfaced via the standard toast pattern; partial state is impossible because the disk move is atomic-then-DB-then-memory.

**Future extension flagged.** "Move to…" on a *Folder* row (move a whole Folder between Collections) is not part of v1 — Folders are structurally fixed to their parent Collection at creation time. If a user wants to relocate a Folder, they delete and recreate it (or drag the folder in Finder; the next launch's auto-tag walk re-classifies it). A first-class Folder-move action is a Prospect.

#### Wikilinks, Relations, Search

No changes. Wikilinks resolve by Page ID (immutable across moves); Relations store target IDs in frontmatter and resolve through `PageContentManager` regardless of container depth. The existing relation-picker (`RelationPicker.swift`) lists Pages by their resolved title, indifferent to whether the page lives in a Folder.

#### Nexus Adoption Pipeline + Auto-Sidecar Tagging

[NexusAdopter](Pommora/Pommora/Nexus/NexusAdopter.swift) gains both depth extension and a new auto-tagging pass. Folders are first-class citizens of the filesystem-and-Nexus model: anything visible on disk inside a Collection without a `_folder.json` gets one stamped on launch so the user can build structure via Finder.

**1. Depth extension — recognize Folder sidecars at the third tier.** `AdoptedSidecarKind` ([NexusAdopter.swift:40–58](Pommora/Pommora/Nexus/NexusAdopter.swift#L40-L58)) gains `case folder` whose `filename` returns `NexusPaths.folderSidecarFilename`. The recognized-sidecar set at [NexusAdopter.swift:260–267](Pommora/Pommora/Nexus/NexusAdopter.swift#L260-L267) gains `_folder.json`. The legacy-orphan cleanup pass ([NexusAdopter.swift:808–819](Pommora/Pommora/Nexus/NexusAdopter.swift#L808-L819)) extends to walk one level deeper inside each Collection so a Folder folder's own sidecar isn't mistakenly classified as a co-located orphan.

**2. Silent auto-sidecar-tagging pass (paradigm shift, locked this session).** New method `NexusAdopter.autoTagMissingSidecars(at: nexusRoot)` walks the Nexus root **three levels deep on every launch** and silently writes missing per-kind sidecars. Idempotent + silent — no user prompt. Skips dotfile-prefixed (`.nexus/`, `.obsidian/`, `.trash/`) and underscore-prefixed folder names. Failures logged to stderr; never abort launch.

Depth-aware kind selection:

- **Depth 0** (Nexus root child folder lacking any recognized sidecar) → content-sniff via existing `contentSniff` ([NexusAdopter.swift:527–549](Pommora/Pommora/Nexus/NexusAdopter.swift#L527-L549)). `.md` descendants → `_pagetype.json`. User `.json` descendants → `_itemtype.json`. Empty → `_pagetype.json` default.
- **Depth 1, parent has `_pagetype.json`** → write `_pagecollection.json` (no content-sniff; kind is dictated by parent).
- **Depth 1, parent has `_itemtype.json`** → write `_itemcollection.json`.
- **Depth 2, parent has `_pagecollection.json`** → write `_folder.json` (the new tier).
- **Depth 2, parent has `_itemcollection.json`** → no-op (Items side has no third tier).

The fresh-sidecar writer reuses `writeFreshSidecar` ([NexusAdopter.swift:635–683](Pommora/Pommora/Nexus/NexusAdopter.swift#L635-L683)) — extended with a `.pageCollection` / `.itemCollection` / `.folder` case that mints a minimal sidecar carrying `id: ULID.generate()`, the right `type_id` / `collection_id` parent pointers (resolved from the parent's loaded sidecar), `modified_at: now`, and `schema_version: 1`. For Folders specifically: the discovery pass also fills `icon: nil` (user picks one later via the View Settings popover), empty `page_order`, empty `views` (the default Table view gets minted lazily by `PageTypeManager.loadAll`'s default-view migration on next load, per the existing pattern at [PageTypeManager.swift:63–68](Pommora/Pommora/Vaults/PageTypeManager.swift#L63-L68)).

**Paradigm-shift note.** The existing `hasAnythingToAdopt` gate ([NexusAdopter.swift:195–203](Pommora/Pommora/Nexus/NexusAdopter.swift#L195-L203)) deliberately kept fresh top-level folders invisible to discovery — *"non-Pommora folders at root stay invisible to discovery (per-folder adoption UI is a future Prospect)."* The auto-tagging pass overrides that decision. **Consequence:** any non-Pommora folder a user keeps at the Nexus root (e.g. an Obsidian vault, an unrelated working folder) without a dotfile/underscore prefix will receive a `_pagetype.json` on next launch. This is the cost of "build via Finder" — the user has chosen this Nexus as a Pommora root and accepts that everything inside is presumed Pommora-tagged. Log this in `// Guidelines//Paradigm-Decisions.md` as the next numbered decision.

#### Launch Flow

The launch sequence in [NexusManager.runAdoptionIfNeeded](Pommora/Pommora/Nexus/NexusManager.swift#L268-L329) extends:

1. `NexusAdopter.scan(nexusRoot:)` — builds legacy-migration plan (unchanged)
2. If `plan.hasAnythingToAdopt` → show `AdoptionPreviewView` sheet → `NexusAdopter.apply(plan)` on confirm (unchanged)
3. **NEW:** `NexusAdopter.autoTagMissingSidecars(at: nexusRoot)` — runs unconditionally after step 2 completes (whether sheet shown or not, confirmed or declined). Silent. Idempotent.
4. `openIndex(for: nexus)` → `IndexBuilder.populate(index:from:)` walks the now-fully-tagged tree and populates SQLite (existing — quirk #15 defensive upserts on `loadAll` cover any sidecars that landed between steps 3 and 4)

Order is critical: auto-tag runs before IndexBuilder so the wipe-and-rebuild walk sees every folder pre-tagged with its correct sidecar.

#### Per-Nexus State (state.json)

[NexusState](Pommora/Pommora/NavDropdown/NexusState.swift) at `<nexus>/.nexus/state.json` carries `recents`, `pinned`, `cursor`, and four top-level section-order arrays ([NexusState.swift:13–26](Pommora/Pommora/NavDropdown/NexusState.swift#L13-L26)). **No new fields.** Per-Collection state (Folder ordering inside Collections via the new `folder_order` field) lives in `_pagecollection.json` — matching the established pattern where per-Collection state lives in the Collection sidecar, not state.json. The `pinned` array holds `EntityStateRef` objects keyed by `(kind, id)`; adding `.folder` to `EntityStateRef.Kind` is the only state.json-adjacent change, and it's backward-compatible (legacy state files decode fine; the new kind appears only when a Folder is pinned).

[NexusContext](Pommora/Pommora/Validation/NexusContext.swift) is the lookup-closure context for cross-entity validation. **No change** — Folder validation only requires sibling-uniqueness within the parent Collection, which the FolderManager (extension on PageTypeManager) checks directly against its own `foldersByCollection[collectionID]` dictionary. No new lookup closure needed.

#### Files Created (new)

- [Pommora/Pommora/CRUD/CreateWithInlineEdit.swift](Pommora/Pommora/CRUD/CreateWithInlineEdit.swift) — shared stub-and-inline-rename coordinator used by every entity-creation path (PageType, PageCollection, Folder, Page, ItemType, ItemCollection, Item)
- [Pommora/Pommora/CRUD/DefaultTitleResolver.swift](Pommora/Pommora/CRUD/DefaultTitleResolver.swift) — generates `"New <Label>"` / `"New <Label> 2"` / `"New <Label> 3"` with integer disambiguator based on existing siblings
- [Pommora/Pommora/Vaults/Folder.swift](Pommora/Pommora/Vaults/Folder.swift)
- [Pommora/Pommora/Sidebar/FolderRow.swift](Pommora/Pommora/Sidebar/FolderRow.swift)
- [Pommora/Pommora/Detail/FolderDetailView.swift](Pommora/Pommora/Detail/FolderDetailView.swift)
- [PommoraTests/FolderTests.swift](PommoraTests/FolderTests.swift) — model codable round-trip + load/save
- [PommoraTests/PageTypeManager+FolderCRUDTests.swift](PommoraTests/PageTypeManager+FolderCRUDTests.swift) — create / rename / delete / reorder
- [PommoraTests/FolderIndexSyncTests.swift](PommoraTests/FolderIndexSyncTests.swift) — loadAll → SQLite parity (quirk #15 mirror)
- [PommoraTests/PageMoveTests.swift](PommoraTests/PageMoveTests.swift) — backend `movePage` between every (Type-root | Collection-root | Folder) destination pairing
- [PommoraTests/NexusAdopter+AutoTagTests.swift](PommoraTests/NexusAdopter+AutoTagTests.swift) — Finder-built structures (empty Nexus root with hand-created `MyType/MyCollection/MyTopic/note.md` and zero sidecars) round-trip through `autoTagMissingSidecars` → IndexBuilder → SQLite with correct three-tier FK trio populated; idempotence (running twice produces identical disk state); dotfile/underscore exclusion (`.obsidian/` left alone)
- [PommoraTests/CreateWithInlineEditTests.swift](PommoraTests/CreateWithInlineEditTests.swift) — every entity type (PageType, PageCollection, Folder, Page, ItemType, ItemCollection, Item) stubs with the correct default title from settings labels; `DefaultTitleResolver` disambiguates against existing siblings (`"New Folder"` → `"New Folder 2"` → `"New Folder 3"`); the row's `editingID` flips to the new entity's ID after creation; rename-commit validators reject collisions and surface the standard error treatment without re-opening any sheet

#### Files Modified

- [Pommora/Pommora/AtomicIO/NexusPaths.swift](Pommora/Pommora/AtomicIO/NexusPaths.swift) — sidecar filename + path helper
- [Pommora/Pommora/Nexus/NexusAdopter.swift](Pommora/Pommora/Nexus/NexusAdopter.swift) — `AdoptedSidecarKind.folder` + recognized-sidecar set + third-tier orphan cleanup + new `autoTagMissingSidecars(at:)` silent-discovery pass
- [Pommora/Pommora/Nexus/NexusManager.swift](Pommora/Pommora/Nexus/NexusManager.swift) — call `autoTagMissingSidecars` unconditionally in `runAdoptionIfNeeded` after the legacy `apply` pass completes (step 3 of launch flow)
- [Pommora/Pommora/Vaults/PageTypeManager.swift](Pommora/Pommora/Vaults/PageTypeManager.swift) — `foldersByCollection` + CRUD + loadAll extension
- [Pommora/Pommora/Pages/PageContentManager.swift](Pommora/Pommora/Pages/PageContentManager.swift) — `pagesByFolder` + accessors + `resolveParent` extension
- [Pommora/Pommora/Pages/PageContentManager+CRUD.swift](Pommora/Pommora/Pages/PageContentManager+CRUD.swift) — optional `folder:` parameter on page-creation
- [Pommora/Pommora/Index/IndexSchema.swift](Pommora/Pommora/Index/IndexSchema.swift) — new `folders` table + `page_folder_id` column + indexes (additive migration)
- [Pommora/Pommora/Index/IndexBuilder.swift](Pommora/Pommora/Index/IndexBuilder.swift) — `FolderSnapshot` + three-level walk + Page FK routing
- [Pommora/Pommora/Index/IndexQuery.swift](Pommora/Pommora/Index/IndexQuery.swift) — `.folder(folderID)` query scope
- [Pommora/Pommora/Index/IndexUpdater.swift](Pommora/Pommora/Index/IndexUpdater.swift) — folder upsert + delete helpers
- [Pommora/Pommora/Sidebar/SidebarSelection.swift](Pommora/Pommora/Sidebar/SidebarSelection.swift) — `.folder` cases on both `SidebarSelection` + `SelectionTag` + lookup
- [Pommora/Pommora/Sidebar/PageCollectionRow.swift](Pommora/Pommora/Sidebar/PageCollectionRow.swift) — `CollectionChildItem` enum + Folder/Page ForEach + context menu "New Folder"
- [Pommora/Pommora/Sidebar/PageTypeRow.swift](Pommora/Pommora/Sidebar/PageTypeRow.swift) — no structural change but verify `VaultDisclosureItem` enum still type-checks once `PageParent` extends
- [Pommora/Pommora/Sidebar/PageRow.swift](Pommora/Pommora/Sidebar/PageRow.swift) — handle new `PageParent.folder(...)` case
- [Pommora/Pommora/Sidebar/SidebarView.swift](Pommora/Pommora/Sidebar/SidebarView.swift) — "Move to ▸" nested-Menu construction inside Page row context menus (recursive Vault/Collection/Folder tree builder)
- [Pommora/Pommora/Detail/PageCollectionDetailView.swift](Pommora/Pommora/Detail/PageCollectionDetailView.swift) — Folder rows render above Page rows (analog to Collection detail showing nested entities first); "New Folder" context entry
- [Pommora/Pommora/ContentView.swift](Pommora/Pommora/ContentView.swift) — detail dispatch + env injection chain for Folder
- [Pommora/Pommora/ViewSettings/StorageMenuRoot.swift](Pommora/Pommora/ViewSettings/StorageMenuRoot.swift) — `.folder` scope; tappable icon affordance for Folder; display-only title
- [Pommora/Pommora/NavDropdown/EntityStateRef.swift](Pommora/Pommora/NavDropdown/EntityStateRef.swift) — `.folder` kind + bridge case
- [Pommora/Pommora/Settings/SettingsLabels.swift](Pommora/Pommora/Settings/SettingsLabels.swift) — `folder: LabelPair`
- [.claude/Features/PageTypes.md](.claude/Features/PageTypes.md) — document Folder tier
- [.claude/Features/Pages.md](.claude/Features/Pages.md) — describe Folder containment
- [.claude/Features/Sidebar.md](.claude/Features/Sidebar.md) — three-level row vocabulary
- [.claude/Features/Domain-Model.md](.claude/Features/Domain-Model.md) — Pages-side three-layer note
- [.claude/Handoff.md](.claude/Handoff.md) — current-state update
- [.claude/History.md](.claude/History.md) — locked decision log entry

Quirk #2 (`PBXFileSystemSynchronizedRootGroup`) means new Swift files auto-include — no pbxproj edits needed for the new files above.

#### Phasing (Per Quirk #8, Stub-and-Progressively-Replace)

**Phase F.0 — CRUD pattern refactor (system-wide pre-work).** Refactor every existing "New X" CRUD UI to stub-and-inline-rename. Add [Pommora/Pommora/CRUD/CreateWithInlineEdit.swift](Pommora/Pommora/CRUD/CreateWithInlineEdit.swift) shared coordinator. Convert PageType, PageCollection, Page, ItemType, ItemCollection, Item creation paths in this order. Delete the corresponding `New*Sheet.swift` files and remove their `SidebarSheet` cases + routing. Move validators from sheet-driven to commit-driven (existing validator types preserved; invocation site shifts to the rename-commit path). Tests: every entity-type stubs with the correct default title, disambiguator runs on existing-sibling collisions, focus lands on the new row's TextField, Enter commits via rename, Esc leaves the stub created. Ship green — this phase is shippable independently of Folders.

**Phase F.1 — Folder schema + model + adopter + auto-tag.** Add `Folder.swift`, `_folder.json` sidecar, SQLite migration, IndexBuilder three-level walk. **Also lands the NexusAdopter extension + `autoTagMissingSidecars` silent-discovery pass** so Finder-built structures show up in the index from day one. Manager loads Folders but no UI surfaces them yet. Tests: codable round-trip, loadAll → SQLite parity, NexusAdopter auto-tag idempotence, Finder-built-three-tier round-trip. Ship green.

**Phase F.2 — Sidebar visibility.** Wire Folders into the sidebar tree under Collections. `FolderRow` renders, `SelectionTag.folder` routes through `ContentView.detail` to a stub `FolderDetailView` (plain title + "TBD"). Pinned + Back/Forward round-trips work. Tests: row diff (quirk #9), selection routing, EntityStateRef bridge.

**Phase F.3 — Folder CRUD.** Wire "New Folder" via the F.0 `CreateWithInlineEdit` coordinator (stub `"New Folder"` + inline-rename), plus rename, delete, reorder. `New Page (in This Folder)` from the Folder row context menu — same stub-and-edit pattern. SQLite upsert/delete wired. Tests: PageTypeManager folder CRUD, page-creation inside Folder, default-title disambiguator on second/third creation, validator reject on Enter-commit collision.

**Phase F.4 — Detail surface.** Real `FolderDetailView` (mirror of `PageCollectionDetailView`), View Settings popover + icon picker, drag-reorder of Pages inside the Folder. Tests: detail view loads, view settings binds to `views[0]`.

**Phase F.5 — Documentation + Settings.** Update `.claude/Features/*.md`, `Handoff.md`, `History.md`. Add `folder: LabelPair` to settings. Ship as the user-facing release.

Each phase passes `swift format lint --strict --recursive Pommora/` and `xcodebuild -only-testing:PommoraTests` clean before merging.

#### Verification

End-to-end manual test once Phase F.5 ships:

1. Launch Pommora against a Nexus with at least one Page Type that has at least one Page Collection.
2. Right-click the Collection in the sidebar → "New Folder". A new row labeled "New Folder" appears immediately under the Collection in inline-rename mode (text field focused). Type "Topic A" + Enter. The row renames; on disk, `<Collection>/Topic A/_folder.json` now exists. No modal sheet appeared at any point.
3. Right-click the Folder → "New Page" → name it "Note 1". A `.md` file appears inside the Folder folder; the Page opens in the editor.
4. Inspect SQLite (via debugger or test fixture): `SELECT page_folder_id, page_collection_id, page_type_id FROM pages WHERE title = 'Note 1'` — all three columns populated.
5. Select the Folder in the sidebar → `FolderDetailView` renders with Note 1 in the list.
6. Open the View Settings popover from the toolbar → confirm the icon is tappable and a `SymbolPicker` opens; pick a new symbol; the new icon shows in the sidebar and detail header.
7. Toggle a property in the Property Visibility pane → confirm `_folder.json`'s `views[0].hidden_properties` updates on disk.
8. Pin the Folder from the right-click menu → confirm it appears in the NavDropdown's Pinned section; quit and relaunch — pinned entry restores.
9. Open Note 1, then back-step (Cmd-[): cursor returns to the previously-viewed Page or selection, NOT to the Folder (Folders are not Recents-recordable).
10. Right-click the Folder → Delete → confirm cascade: SQLite folders row gone; `page_folder_id` of the now-orphaned Page is null (ON DELETE SET NULL); file structure on disk reflects deletion.
11. **Finder-driven structure test (validates auto-tagging).** Quit Pommora. In Finder, inside the Nexus root, create a new folder `Research/`. Inside it, create `Sources/`. Inside that, create `2026-Q2/`. Inside that, create `paper.md` with arbitrary Markdown content. Launch Pommora. Without any clicks, the sidebar should show: a new Page Type "Research" → Page Collection "Sources" → Folder "2026-Q2" → Page "paper". Inspect on disk: `_pagetype.json`, `_pagecollection.json`, and `_folder.json` should each have been written silently with valid `id` / `type_id` / `collection_id` fields. SQLite should have the page's `page_type_id` + `page_collection_id` + `page_folder_id` all populated.
12. **Auto-tag exclusion test.** Quit Pommora. In Finder, create `.obsidian/` and `_misc/` (dotfile + underscore prefixes) at the Nexus root, populated with arbitrary content. Launch Pommora. Confirm neither folder gets a `_pagetype.json` — they stay invisible to discovery per the prefix-skip rule.
13. **Idempotence test.** Quit and relaunch immediately. Confirm no duplicate sidecars are written and on-disk state is identical to step 11's outcome.

Run automated tests:

```
xcodebuild test -scheme Pommora -only-testing:PommoraTests/FolderTests \
  -only-testing:PommoraTests/PageTypeManager_FolderCRUDTests \
  -only-testing:PommoraTests/FolderIndexSyncTests
```

(Quirk #1: filter form is `<FilenameWithTests>`, not the `@Suite` name.)

#### Execution Discipline

**Implementation is done in-line by Claude directly — no code-writing delegated to subagents.** Decision locked this session. Every code change, test, and edit goes through Claude's own tools so context stays correct across the multi-phase rollout. Phase boundaries are still observed (F.0 → F.1 → F.2 → F.3 → F.4 → F.5), but each phase is hand-implemented step by step in the same session (or continued across sessions via Handoff.md), not handed off to a feature-dev or general-purpose agent.

The one carve-out is build verification: xcodebuild runs may still go through a background `building-apple-platform-products` agent per quirk #14 so that `xcodebuild test` doesn't grab window focus during Nathan's work. That's a focus-theft mitigation, not code delegation — Claude still writes every line.

#### Out of Scope

- Items side (Item Type → Item Collection → Folder?) — explicitly excluded; not a feature need.
- Folder-scope properties or schema override (Folders inherit from parent Type, like Collections).
- Whole-Folder hide-from-sidebar (`hidden: Bool`) — explicitly excluded from v1 this session. Per-view property column visibility lives inside `views[0].hiddenProperties` (already covered by the standard View Settings popover).
- Cross-container moves via sidebar drag — drag is exclusively same-zone reorder; cross-container moves go through the "Move to…" context-menu sheet on a Page row in any container.
- First-class Folder relocation (moving a whole Folder between Collections) — Folders are structurally fixed to their parent Collection at creation. Relocate by deleting and recreating, or by Finder-moving the folder and letting the next launch's auto-tag pass re-classify it. A dedicated affordance is a Prospect.
- Manual "Convert to Folder" affordance for sub-sub-folders — auto-tagging handles this automatically on next launch, so the explicit UI affordance is unnecessary at v1. A "this folder is not a Folder" opt-out sentinel is a Prospect for users who want to keep specific sub-sub-folders unclassified.
- Cloud-sync / cross-nexus reconciliation — no changes; the additive on-disk pattern is portable by design.
