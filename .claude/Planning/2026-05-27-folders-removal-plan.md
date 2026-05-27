### Plan — Folders Feature Removal (Revert F.1–F.4, Keep F.0 + Auto-Tag)

> Reverts the Folders third-tier feature in full. Folders were built ahead of the view-organization system (Board / group-by / saved views, v0.6.0) that would justify a structural tier; the rigid-grouping role duplicates Collections, and the group-by-vs-hierarchy conflict is unresolved. Removing now (cheapest exit) before more features build on the third tier. Decision + reasoning: this session's chat.

#### Keep-list (do NOT remove)

1. **F.0 CRUD UX** (commit `68caf96`) — stub-and-inline-rename, `CreateWithInlineEdit`, `DefaultTitleResolver`. Untouched by this revert.
2. **Sidebar context-menu tweaks** (from `0f6d365`) — "New Vault" removed from the PageType row context menu (the Pages-section "+" header is the sole vault-creation path); "(in This X)" suffix dropped from PageCollectionRow / ItemCollectionRow / TopicRow create actions. Preserve these edits; only strip the folder-specific lines from the same files.
3. **Auto-tagging for Types + Collections** (`NexusAdopter.autoTagMissingSidecars`, `NexusManager` wiring) — lets a user drag folders into a Nexus via Finder and have Types/Collections recognized. KEEP `tagDepth0IfMissing`, `walkDepth1`, `tagDepth1IfMissing`, `writeAutoTagTypeSidecar`, `writeAutoTagCollectionSidecar`. REMOVE only the depth-2 folder layer (`walkDepth2`, `tagDepth2IfMissing`, `writeAutoTagFolderSidecar`, `AdoptedSidecarKind.folder`).

#### SQLite note

`IndexSchema.apply` is idempotent `CREATE TABLE IF NOT EXISTS` (not a GRDB migrator). Removing the `folders` DDL + `page_folder_id` column + 3 indexes is clean: fresh DBs won't carry them. Existing dev DBs keep a dormant `folders` table + column until the `.sqlite` is regenerated (harmless — the index is regeneratable; IndexBuilder wipes + repopulates). No drop-migration required.

#### Whole-file deletions (8)

Production (4):
- `Pommora/Pommora/Vaults/Folder.swift`
- `Pommora/Pommora/Sidebar/FolderRow.swift`
- `Pommora/Pommora/Detail/FolderDetailView.swift`
- `Pommora/Pommora/Validation/FolderValidator.swift`

Tests (4 — 100% folder):
- `Pommora/PommoraTests/Vaults/FolderTests.swift`
- `Pommora/PommoraTests/Vaults/PageTypeManagerFolderCRUDTests.swift`
- `Pommora/PommoraTests/Content/PageContentManagerFolderTests.swift`
- `Pommora/PommoraTests/Validation/FolderValidatorTests.swift`
- `Pommora/PommoraTests/Nexus/FolderIndexSyncTests.swift` (5th — 100% folder)

#### Surgical edits — UI layer

- `Sidebar/SidebarSelection.swift` — remove `SidebarSelection.folder`, `SelectionTag.folder`, the `.matches` folder pair, `SelectionTag.init` folder case, both resolver-bridge folder cases, the `pagesByFolder` loop in `init?(tag:)`.
- `Sidebar/SidebarConfirmation.swift` — remove `deleteFolder` case + its `id` branch.
- `Sidebar/SidebarView.swift` — remove `deleteFolder` dialog title/message/buttons branches.
- `Sidebar/PageCollectionRow.swift` — revert `CollectionChildItem` back to pages-only `ForEach` over `contentManager.pages(in:)`; remove `.folder` enum case, FolderRow rendering, `isCreatingFolder`, `createFolder()`, "New Folder" context button, folder branch in `reorder()`. KEEP "New Page" (plain label).
- `Sidebar/PageRow.swift` — remove `.folder` cases in `commit()` + `delete()`.
- `Content/PageParent.swift` — remove `case folder(Folder, vault:)`.
- `Detail/PageCollectionDetailView.swift` — remove `isCreatingFolder`, `@Environment(PageTypeManager)` (verify no other use), "New Folder" footer button, `createFolder()`.
- `Detail/PageTypeDetailView.swift` — remove `.folder` cases in rename + delete `PageParent` switches.
- `Detail/SidebarDetailView.swift` — remove `.folder` routing case + `lookupVault(forFolder:)`.
- `ContentView.swift` — remove `.folder` case in `viewSettingsScope(for:)`.
- `NavDropdown/EntityStateRef.swift` — remove `Kind.folder` + sidebarSelection bridge case.
- `NavDropdown/EntityRow.swift` — remove `.folder` in `iconName` + `chipText`.
- `NavDropdown/NavDropdownButton.swift` — remove `.folder` from `handleOpen` case group.
- `NavDropdown/BackForwardButtons.swift` — remove `.folder` from `applyStep` case group.

#### Surgical edits — data layer

- `Vaults/PageTypeManager.swift` — remove `foldersByCollection`, `folders(in:)`, `folder(byID:)`, the loadAll folder walk + default-view migration + `upsertFolder` sync, folder folderURL rebuilds in `renamePageType` + `renamePageCollection`, the entire Folder CRUD section (`createFolder`/`renameFolder`/`updateFolderIcon`/`deleteFolder`/`reorderFolders`), and the folder branch in `updateView`.
- `Content/PageContentManager.swift` — remove `pagesByFolder`, `pages(in folder:)`, `loadAll(for folder:)`, the Collection-walk folder exclusion, `resolveParent` back to 2-tuple, `reorderPages(in folder:)`.
- `Content/PageContentManager+CRUD.swift` — remove the 4 folder-scoped overloads (`createPage`/`renamePage`/`deletePage`/`updatePage` `in folder:`).
- `Ordering/OrderPersister.swift` — remove `setPageOrder(_:in folder:)`, `setFolderOrder`, `mutateFolder`.
- `Vaults/PageCollection.swift` — remove `folderOrder` field + its CodingKey + init param + encode/decode + the two rebuild-site preservations.
- `AtomicIO/NexusPaths.swift` — remove `folderSidecarFilename`, `folderFolderURL`, `folderMetadataURL`.

#### Surgical edits — SQLite / index layer

- `Index/IndexSchema.swift` — remove `foldersDDL` + its execute, `addPageFolderIDColumnIfMissing` + its call, `page_folder_id` line in pagesDDL, 3 folder indexes.
- `Index/IndexBuilder.swift` — remove `FolderSnapshot`, `PageSnapshot.folderID`, folder walk in `collectPageTypes`, `folderID` param on shared `collectPagesInFolder` (KEEP the method — it's the generic per-directory collector used by collection + type-root too), `DELETE FROM folders` in `clearAllTables`, folder inserts in `insertPageTypes`, `page_folder_id` in `insertPage`, folder iteration in `insertRelations`/`insertTierLinks`.
- `Index/IndexQuery.swift` — remove `TargetRef.folder`, its `targetSQL` + `targetEntityKind` branches.
- `Index/IndexUpdater.swift` — remove `upsertFolder`, `deleteFolder`, `pageFolderID:` param on `upsertPage` + all call sites.

#### Surgical edits — adopter (KEEP type/collection auto-tag)

- `Nexus/NexusAdopter.swift` — remove `AdoptedSidecarKind.folder` (+ filename branch), `_folder.json` from `recognizedFlatSidecarFilenames`, `.folder` from `recognizedSidecarsAt`, the third-tier walk in `cleanupLegacyOrphans`, `.folder` from the `writeFreshSidecar` exhaustive switch, `walkDepth2`, `tagDepth2IfMissing`, `writeAutoTagFolderSidecar`, and the `walkDepth2` call inside `walkDepth1`. KEEP everything depth-0 / depth-1.
- `Nexus/AdoptionPreviewView.swift` — remove `.folder` cases in `iconForSidecar` + `labelForSidecar`.
- `Nexus/NexusManager.swift` — NO CHANGE (autoTag call is tier-agnostic; stays).

#### Surgical edits — tests

- `PommoraTests/Nexus/NexusAdopterAutoTagTests.swift` (MIXED) — delete `threeTierPagesRoundTrip`, `threeTierPreservesPageFile`; strip folder assertions from `itemsSideTwoTiersOnly` + `idempotence`; KEEP `skipsDotfilePrefix`, `skipsUnderscorePrefix`, `skipsDotfileChild`, `writesOnlyMissing`.
- `PommoraTests/Index/IndexBuilderTests.swift` — remove folder-tier tests + `setupWithFolder` helper.
- `PommoraTests/Index/IndexQueryTests.swift` — remove `.folder` target tests.
- `PommoraTests/Index/IndexUpdaterTests.swift` — remove folder tests + `makeFolder` factory + `pageFolderID:` usages.
- `PommoraTests/Vaults/PageCollectionTests.swift` — remove `folderOrder` round-trip tests.

#### Docs cleanup

- `.claude/History.md` — delete the v0.3.2 Folders section; replace with a 3–4 sentence "tried and reverted" note.
- `.claude/Handoff.md` — remove all folder commit rows, locked-decision subsections, roadmap lines, resume prompt folder content; rewrite current-state to reflect the revert.
- `.claude/Guidelines/CRUD-Patterns.md` — remove "Folder" from the entity-kind list (KEEP the "Folder + file atomicity" section — that's about Topic *directories*, not the entity).
- `.claude/Planning/2026-05-26-folders-and-stub-crud-refactor-plan.md` — DELETED (the feature is reverted + logged in History as "tried and reverted"; no value in archiving the ~1450-line plan).
- Verify `Features/*.md`, `PommoraPRD.md` carry NO three-tier "Vault → Collection → Folder → Page" language (the F.5 doc pass never shipped, so likely clean — confirm).

#### Execution order

1. Delete the 8 whole files.
2. Surgical UI edits → data edits → SQLite edits → adopter edits → test edits.
3. Background xcodebuild test (full app compile + regression bootstrap).
4. Fix any missed exhaustive switches / references surfaced by the build.
5. Docs cleanup + History "tried and reverted" entry.
6. Commit as a single `revert(folders)` + push to sync the shared main.

#### Codebase health log → see `2026-05-27-codebase-health-log.md`

Bloat / structural concerns surfaced during the sweep are logged separately for future maintenance passes (out of this revert's scope).
