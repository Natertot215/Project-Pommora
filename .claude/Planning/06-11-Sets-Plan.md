## Sets — Implementation Plan (v0.4.1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Sets — the optional third operational tier (Vault → Collection → Set → Pages) per `06-11-Sets-Spec.md` — as v0.4.1.

**Architecture:** New lightweight `PageSet` entity (sidecar `_pageset.json`, no schema/views/settings), dedicated `PageSetManager`, one new SQLite table + one `pages` column, depth-2 adoption, sidebar disclosure rows that expand but never select, set-aware container identification for connections.

**Tech stack:** Swift 6 (strict concurrency, ExistentialAny), SwiftUI + AppKit, GRDB SQLite, swift-testing (`@Suite`/`@Test`).

**Controller loop:** one task = one green commit, dispatched to a fresh subagent that reports back; re-assess this plan against what landed before dispatching the next task (CLAUDE.md hard rule). Only green commits are facts.

**Every subagent dispatch carries the CLAUDE.md "Active branch quirks" block verbatim.** The load-bearing ones here: builder verification via background Agent with `-only-testing:PommoraTests` (test filter matches the `@Suite` name, NOT the filename — every new test file declares `@Suite("<name>")` exactly matching the filter used; ALWAYS verify a non-zero executed count); trust `xcodebuild`, not SourceKit; revert Xcode's pbxproj SPM reorder before commit; never revert unattributed working-tree changes (parallel sessions); sidebar Section structure is load-bearing (quirk #8) — tests must bootstrap, not just compile. Test fixtures use the existing `TempNexus.make()` helper (`PommoraTests/Support/TempNexus.swift`).

---

### Task 1 — PageSet domain type + paths

**Files:**
- Create: `Pommora/Pommora/Vaults/PageSet.swift`
- Modify: `Pommora/Pommora/AtomicIO/NexusPaths.swift` — sidecar constant `pageSetSidecarFilename = "_pageset.json"` beside the others at L7–16; new helpers beside the PageCollection pair at L261–297: `pageSetFolderURL(in:typeFolderName:collectionFolderName:setFolderName:)` + `pageSetMetadataURL(...)` (mirror the collection helpers exactly)
- Modify: `Pommora/Pommora/Vaults/PageCollection.swift` (add `setOrder: [String]?`, CodingKey `set_order`)
- Test: new `@Suite("PageSetCodableTests")` (+ extend the `@Suite("PageCollectionFile")` suite for `set_order`)

`PageSet` mirrors `PageCollection`'s shape (PageCollection.swift:7–111) minus views — sidecar filename lives in NexusPaths only, matching convention (no static constant on the type):

```swift
struct PageSet: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String                  // ULID
    var collectionID: String        // CodingKey "collection_id"
    var title: String               // derived from folder name, NOT persisted
    var folderURL: URL              // runtime only
    var icon: String? = nil         // nil renders as SF Symbol "folder" in UI (Task 7)
    var pageOrder: [String]?        // CodingKey "page_order"
    var modifiedAt: Date            // CodingKey "modified_at"
    var schemaVersion: Int          // CodingKey "schema_version", default 1
}
```

Custom Codable copies PageCollection.swift:65–106 exactly: `init(from decoder: any Decoder)` sets `title = ""` and `folderURL = URL(fileURLWithPath: "/")` (caller overwrites); `load(from metadataURL:)` decodes via `AtomicJSON`, then derives `folderURL = metadataURL.deletingLastPathComponent()` and `title = folderURL.lastPathComponent`. Persistence via the existing `AtomicJSON` (centralized `.iso8601` dates).

- [ ] Write `PageSetCodableTests`: round-trip encode/decode; `load(from:)` derives title + folderURL; decoder leaves title/folderURL placeholders; `set_order` round-trips on PageCollection.
- [ ] Implement `PageSet.swift` + NexusPaths constant/helpers + `PageCollection.setOrder`.
- [ ] Builder (background agent): `-only-testing:PommoraTests/PageSetCodableTests` — non-zero executed count, green.
- [ ] Commit: `feat(sets): PageSet domain type + sidecar paths`

### Task 2 — SQLite schema + index plumbing

**Files:**
- Modify: `Pommora/Pommora/Index/PommoraIndex.swift:101` — `currentSchemaVersion` **13 → 14** (delete-and-rebuild on mismatch, no migration)
- Modify: `Pommora/Pommora/Index/IndexSchema.swift` (new `page_sets` DDL; `pages` gains `page_set_id`; two indices)
- Modify: `Pommora/Pommora/Index/IndexBuilder.swift` — `PageSnapshot` (L28–40) gains `setID: String?`; the type walk collects Sets per Collection; new `insertPageSet` mirroring `insertPageType`/`insertPageCollection` (attemptInsert wrapper); `page_sets` slots between `page_collections` and `pages` in BOTH `clearAllTables` (L379–389) and the insert order (L412–428); `insertPage` (L435) writes `page_set_id`
- Modify: `Pommora/Pommora/Index/IndexUpdater.swift` — `upsertPageSet`/`deletePageSet` mirroring the Collection pair (L86–113); `upsertPage` signature becomes `(_ meta: PageMeta, pageTypeID: String, pageCollectionID: String?, pageSetID: String?)` with a **three-level FK fallback** extending L147–166: try (type+collection+set) → on `SQLITE_CONSTRAINT` with non-nil set, retry (type+collection, set: nil) → on failure with non-nil collection, retry (type only) → else skip + log
- Modify: `Pommora/Pommora/Index/IndexQuery.swift` — `EntityKind` (L598–601) gains `.pageSet`; `kindTableMap` (L13–26) gains `"page_set": "page_sets"`; `EntityContainer` (L642–649) gains `setID: String?` + `setTitle: String?` (nullable, like the collection pair); `entityContainer` (L151–186) adds the optional `page_sets` join and populates both fields
- Modify: `Pommora/Pommora/Index/FilterBuilder.swift` — `entityKindFromString` (L567–579) + `entityKindToOwningTypeKind` (L554–565) gain the `page_set` mappings
- Test: new `@Suite("PageSetIndexTests")`

```sql
CREATE TABLE IF NOT EXISTS page_sets (
    id TEXT PRIMARY KEY,
    page_collection_id TEXT NOT NULL REFERENCES page_collections(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    icon TEXT,
    modified_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1
);
-- NOTE: no order column — ordering is sidecar-resident by existing pattern (page_collections carries none either)
-- pages: + page_set_id TEXT REFERENCES page_sets(id) ON DELETE SET NULL
-- indices: idx_page_sets_page_collection_id, idx_pages_page_set_id
```

`titleCandidates` / `resolveUniqueEntity` / autocomplete need **no changes** — set pages are ordinary `pages` rows (verified IndexQuery.swift:301–340).

- [ ] Write `PageSetIndexTests`: TempNexus fixture (vault/collection/set/page) → IndexBuilder populates all four tables with correct FKs; `entityContainer` returns vault+collection+set IDs and titles for a set page (and nil set fields for a collection page); page upsert with dangling `page_set_id` falls back per the three-level chain (no SQLite error 19 escape).
- [ ] Implement schema + builder + updater + query + FilterBuilder changes.
- [ ] Builder (background agent): full `-only-testing:PommoraTests` (schema bump touches everything) — green.
- [ ] Commit: `feat(sets): page_sets index table + set-aware container identification`

### Task 3 — Connection locating through Sets

**Files:**
- Modify: `Pommora/Pommora/Connections/ConnectionFileLocator.swift:7–13` — extend the existing `container.collectionTitle.map { ... } ?? fallback` fold with the set level: `container.setTitle` (with `collectionTitle`) folds via `NexusPaths.pageSetFolderURL`, else the current two-segment chain
- Verify-only: `WikiLinkPageOpener.swift:15`, `ConnectionCascade.swift:44`, `PageContentManager+CRUD.swift:817` — the only three `entityContainer` consumers (verified); they pass the container through and need no change. Confirm, don't assume.
- Test: extend the ConnectionFileLocator/WikiLink suite with a set-depth fixture

- [ ] Write test: a `[[link]]` to a page inside a Set resolves and locates its file (three-segment fold); a collection-level page still locates (regression).
- [ ] Implement locator fold; confirm the three consumers pass through.
- [ ] Builder (background agent): connections suites — green, non-zero count.
- [ ] Commit: `feat(sets): wikilink file location through set folders`

### Task 4 — PageSetManager (CRUD + heal + index sync)

**Files:**
- Create: `Pommora/Pommora/Vaults/PageSetManager.swift`
- Create: `Pommora/Pommora/Vaults/PageSetValidator.swift` (thin — same shape as `PageCollectionValidator.swift:10–26`, scope `existingInCollection`, reusing the shared `NameCollisionValidator`)
- Modify: `Pommora/Pommora/Vaults/OrderPersister.swift` (L44–62 area): `setPageSetOrder(_ order: [String], in collection: PageCollection)` via the existing `mutatePageCollection` pattern; `setPageOrder(_ order: [String], in set: PageSet)` mutating the set sidecar
- Modify: `Pommora/Pommora/Vaults/PageTypeManager.swift` — new closure property `var onCollectionFolderChanged: ((PageCollection) -> Void)?`; `renamePageCollection` (L377–433) and `renamePageType`'s collection rebuild (L250–262) invoke it per rebuilt collection after a successful save
- Modify: `Pommora/Pommora/Nexus/NexusEnvironment.swift` — stored property `let pageSetManager: PageSetManager` + init assignment + `pageSetMgr.indexUpdater = updater` (after L139) + `.environment(env.pageSetManager)` in `injectNexusEnvironment` (L212–234) + wire `vaultMgr.onCollectionFolderChanged = { [weak setMgr] in setMgr?.rebuildFolderURLs(for: $0) }`. **Load ordering:** pull the vault load out of the `async let` group (L184–200) — `await vaultMgr.loadAll(filter: folderFilter)` first, then `await setMgr.loadAll(collections: vaultMgr.pageCollectionsByType.values.flatMap { $0 }, filter: folderFilter)`, then the remaining managers stay `async let` parallel
- Test: new `@Suite("PageSetManagerTests")`

Manager surface (`@Observable @MainActor final class`):

```swift
var pageSetsByCollection: [String: [PageSet]] = [:]
var indexUpdater: IndexUpdater?
func loadAll(collections: [PageCollection], filter: FolderFilter) async
    // discovers _pageset.json in DIRECT child folders only; heals missing sidecar (rewrite)
    // + collectionID drift (re-point + re-save); defensive index upsert (quirk #14)
func createPageSet(name: String, in collection: PageCollection) async throws -> PageSet
func renamePageSet(_ set: PageSet, to newName: String) async throws
    // atomic folder rename + rollback (copy renamePageCollection); rebuilds contained page URLs
func deletePageSet(_ set: PageSet, mode: SetDeleteMode) async throws
enum SetDeleteMode { case setOnly /* pages move up to collection root FIRST (each re-indexed), then folder trashed */, withPages /* folder trashed whole via Filesystem.moveToTrash */ }
func updatePageSetIcon(_ set: PageSet, to icon: String?) async throws
func reorderPageSets(in collection: PageCollection, fromOffsets: IndexSet, toOffset: Int)
func pageSets(in collection: PageCollection) -> [PageSet]   // ordered per collection.setOrder (OrderResolver tolerates orphaned IDs — verified)
func rebuildFolderURLs(for collection: PageCollection)      // parent rename hook; cascades to contained pages via contentManager note in Task 5
func moveSet(_ set: PageSet, to destination: PageCollection) async throws   // body lands in Task 9; declare in Task 9, not here
```

- [ ] Write `PageSetManagerTests`: create/rename/delete(both modes — `.setOnly` asserts pages re-home to collection root with index re-point; `.withPages` asserts trash)/icon/reorder round-trips on TempNexus; sidecar heal; `collectionID` drift heal; defensive index sync (page CRUD into a Finder-created set works — `LoadAllIndexSyncTests` pattern); collection rename fires `onCollectionFolderChanged` and set folderURLs rebuild.
- [ ] Implement manager + validator + OrderPersister + closure + environment wiring.
- [ ] Builder (background agent): `PageSetManagerTests` + `LoadAllIndexSyncTests` — green, non-zero counts.
- [ ] Commit: `feat(sets): PageSetManager CRUD + NexusEnvironment wiring`

### Task 5 — Page content scoping + PageParent + free moves

**Files:**
- Modify: `Pommora/Pommora/Content/PageContentManager.swift` — `pagesBySet: [String: [PageMeta]]` cache + accessor `pages(in set: PageSet) -> [PageMeta]` (ordered per `set.pageOrder`); new `loadAll(for set: PageSet)`; collection-scoped `loadAll` (L149–177) excludes Set subtrees the same way the type-root walk excludes Collections (L196–208): `childFolders` filtered by `NexusPaths.pageSetSidecarFilename` presence → `descendantFiles(of:excluding:)`; the type-root walk needs no change (Set folders live inside Collection subtrees it already excludes)
- Modify: `Pommora/Pommora/Content/PageParent.swift` — `case set(PageSet, collection: PageCollection, vault: PageType)`
- Modify: `Pommora/Pommora/Content/PageContentManager+CRUD.swift` — create/rename/delete/update overloads `in: PageSet`; `movePageToSet` / `movePageOutOfSet` (all in-vault combinations strip-free); cross-vault strip path untouched; `reorderPages(in set:)` persisting `set.pageOrder`
- **PageParent ripple — the compiler will surface these; budget them all** (15 files, ~25 sites, enumerated by review): `PageRow.swift:80–85, 102–107` (rename/delete actions), `PageTypeRow.swift:74`, `PageCollectionRow.swift:26`, `PageTypeDetailView.swift:434–437, 471–474`, `SidebarDetailView.swift:63`, `ContentView.swift:64`, `DetailRow.swift:22, 35`, `DetailReorderPlanner.swift:61`, `SidebarSelection.swift:26, 122, 144, 183`, `EntityRow.swift:64, 77`, `EntityStateRef.swift:52`, `PageCollectionDetailView.swift:195, 274, 301, 315` — handle `.set` by delegating to the collection-shaped path (open-in routing already resolves via the vault; verified `PageOpenRouting.swift:24–38` needs no change)
- Test: new `@Suite("PageSetContentTests")`

- [ ] Write `PageSetContentTests`: set pages load into `pagesBySet`, NOT the collection roll-up; collection load returns root pages only; page CRUD in a set (index rows carry `page_set_id`); moves set↔collection-root↔vault-root↔other-set preserve all properties (no strip); cross-vault move still strips (regression); `reorderPages(in set:)` persists.
- [ ] Implement; fix every PageParent site listed above.
- [ ] Builder (background agent): full `-only-testing:PommoraTests` — green.
- [ ] Commit: `feat(sets): set-scoped page content + strip-free in-vault moves`

### Task 6 — Adoption depth-2 + shared ULID-collision healing

**Files:**
- Modify: `Pommora/Pommora/Nexus/NexusAdopter.swift` — `AdoptedSidecarKind` gains `.pageSet`; `recognizedSidecarsAt` ordering includes it after `.pageCollection`; new pair mirroring L684–700 exactly:
  ```swift
  private static func walkDepth2(_ collectionFolder: URL, collectionID: String, now: Date, filter: FolderFilter = .empty)
  private static func tagDepth2IfMissing(_ folder: URL, collectionID: String, now: Date)
  ```
  called from `walkDepth1` for each collection child after its tag (passing the same `filter`); `writeAutoTagSetSidecar` mirrors the collection writer; depth-3+ stays sidecar-less → roll-up; doc comments updated ("three tiers"); adoption preview labels depth-2 folders with the Set label; `cleanupLegacyOrphans` reasoning re-checked at depth 2 (a Set folder's sole recognized sidecar is `_pageset.json`)
- Create: `Pommora/Pommora/Vaults/ContainerIDHealer.swift` — ONE shared helper (DRY): `heal<T: Identifiable>(_ items: [T], reID: (inout T) -> Void, save: (T) throws -> Void) -> [T]` minting a fresh ULID for any later-discovered duplicate ID and re-saving its sidecar; called from `PageTypeManager.loadAll` (collections) AND `PageSetManager.loadAll` (sets). Safe: nothing references container IDs from frontmatter or state.json (verified — order arrays carry vault/context IDs only; index FKs are `ON DELETE SET NULL`; rebuild re-derives from paths)
- Test: extend the NexusAdopter suite + new `@Suite("ContainerIDHealerTests")`

- [ ] Write tests: Finder-shaped fixture (vault/collection/set, no sidecars) → all three tagged on adopt; depth-3 folder gets no sidecar, its page rolls into the set; excluded path at depth 2 untouched; duplicated collection folder AND duplicated set folder each get a fresh ULID on load (both sidecars rewritten, index has two distinct rows).
- [ ] Implement.
- [ ] Builder (background agent): adopter + healer + manager suites — green, non-zero counts.
- [ ] Commit: `feat(sets): depth-2 adoption + shared container ULID-collision healing`

### Task 7 — Sidebar: PageSetRow + reorder + creation + label

**Files:**
- Modify: `Pommora/Pommora/Settings/SettingsLabels.swift` — `pageSet: LabelPair` added to the struct + `defaults()` with `("Set", "Sets")`; decodes nil-default like `excludedFolders` did — **no `defaultsVersion` bump** (`SettingsManager.updateLabel(\.pageSet.singular, ...)` works unchanged). Added here, not Task 10, because this task consumes it — matching how `PageTypeRow.createPageCollection` (L212–236) reads `settingsManager.settings.labels.pageCollection.singular`.
- Create: `Pommora/Pommora/Sidebar/PageSetRow.swift` — disclosure row: icon (`set.icon ?? "folder"`) + title; expands to `PageRow`s with `parent: .set(set, collection:, vault:)`; **NO `.tag()`** (untagged rows are natively non-selectable and skipped by keyboard traversal — verified against `SidebarView.swift:24–98` selection mapping); label switches on `editingID == set.id` for RenameableRow inline-rename, mirroring PageCollectionRow; context menu: New Page / Rename / Change Icon (`.iconPickerPopover`) / Move to… (Task 9 wires the action) / Delete
- Modify: `Pommora/Pommora/Sidebar/PageCollectionRow.swift:22–39` — body becomes a `CollectionDisclosureItem` enum ForEach (`case set(PageSet)` / `case page(PageMeta)`, sets first), copying `PageTypeRow`'s `VaultDisclosureItem` (L10–20, 50–53); single `.onMove` with the two-zone offset translation copied from `PageTypeRow.reorder` (L303–341): sets zone → `pageSetManager.reorderPageSets`, pages zone → existing, cross-zone rejected; context menu gains "New Set" copying `createPageCollection` (L212–236) with `DefaultTitleResolver` + `CreateWithInlineEdit` + the `pageSet` label
- Modify: `Pommora/Pommora/Sidebar/SidebarConfirmation.swift` + `SidebarView.swift` (L188–196 area) — new `.deleteSet(PageSet)` case; its dialog offers the TWO modes per spec: "Delete Set Only" (`.setOnly`) / "Delete Set and Pages" (`.withPages`, destructive) / Cancel
- Test: manager-level reorder/creation suites + full-target bootstrap

Quirk #8 assessment (verified): the mixed disclosure+leaf ForEach body is the proven `PageTypeRow` shape; nesting reaches three disclosure levels for the first time, but the mix stays inside a local ForEach, never at an outer `Section` boundary. The full-target test run must bootstrap the app (OutlineListCoordinator crash check).

- [ ] Write/extend tests: reorder persistence (`setOrder`); inline-create default titles via the label ("Set", "Set 2"…); delete confirmation modes mapped to `SetDeleteMode`.
- [ ] Implement label + rows + menus + confirmation.
- [ ] Builder (background agent): FULL `-only-testing:PommoraTests` — must bootstrap, green.
- [ ] Commit: `feat(sets): sidebar set rows, two-zone reorder, inline creation`

### Task 8 — Breadcrumbs + footer + detail surfacing

**Files:**
- Modify: `Pommora/Pommora/Pages/PageEditorView.swift` — gains an optional `set: PageSet?` parameter mirroring `collection` (the router resolves it from `PageParent.set` — no async lookup needed); `breadcrumbCrumbs` (L187–198) inserts `FooterCrumb(title: set.title)` with nil action between collection and page
- Modify: `Pommora/Pommora/Detail/SidebarDetailView.swift` + every editor-routing site — thread the set from the `.set` PageParent case into the editor
- Modify: `Pommora/Pommora/Detail/PageCollectionDetailView.swift` — **rows** (L246–257): root pages first (ordered per `collection.pageOrder` via `contentManager.pages(in: collection)`), then each Set's pages appended in `collection.setOrder` order, each ordered per `set.pageOrder` via `contentManager.pages(in: set)` — flat concatenation until the Views cluster ships grouping; footer crumbs include the set for set-page trails; `FooterAddMenuButton` items (L209–214) gain `.init(label: "New \(labels.pageSet.singular)", ...)` firing the same `DefaultTitleResolver` + `CreateWithInlineEdit` create as the sidebar
- Test: extend detail/editor suites for crumb composition + row concatenation order

- [ ] Write/extend tests: crumb composition (set segment present + non-actionable; absent for collection-root pages); row order = root pages, then sets in `setOrder`, each per its `pageOrder`; footer create-set.
- [ ] Implement.
- [ ] Builder (background agent): full target — green.
- [ ] Commit: `feat(sets): set breadcrumb segment + footer New Set + flat set-page surfacing`

### Task 9 — Whole-Set moves

**Files:**
- Modify: `Pommora/Pommora/Vaults/PageSetManager.swift` — `moveSet(_ set: PageSet, to destination: PageCollection) async throws`:
  - validate destination title collision (PageSetValidator against destination's sets) — throw before any disk change
  - same-vault: `Filesystem` folder move → re-save sidecar with updated `collectionID` → index re-point (set row + every contained page row's `page_collection_id`; `page_set_id` unchanged) → cache fix-up both collections → contained page `folderURL` rebuild
  - cross-vault: compute per-page strip via the existing `moveStripCount` primitive, surface ONE batched `MoveStripConfirmationDialog` (total count), then per-page name-matched strip + the same move mechanics
- Modify: `Pommora/Pommora/Sidebar/PageSetRow.swift` — wire the "Move to…" `Menu` stubbed in Task 7: **no filesystem move-menu precedent exists** (verified — `PageTypeRow.swift:152–161`'s "Move to Section" is navigation-only metadata); copy only its `Menu { ForEach(targets) { Button } }` *shape*: targets = every collection in the nexus labeled "<vault> › <collection>", current collection disabled
- Test: extend `PageSetManagerTests`

- [ ] Write tests: same-vault set move relocates folder + sidecar `collectionID` + all page rows re-scope, zero property change; cross-vault set move strips per page (count matches `moveStripCount`); destination title collision throws pre-move.
- [ ] Implement.
- [ ] Builder (background agent): manager + index suites — green, non-zero counts.
- [ ] Commit: `feat(sets): whole-set moves between collections`

### Task 10 — Version bump + final gate

**Files:**
- Modify: `Pommora/Pommora.xcodeproj/project.pbxproj` — `MARKETING_VERSION = 0.4.0` → `0.4.1` (both production configurations; `CURRENT_PROJECT_VERSION` untouched; no Info.plist — `GENERATE_INFOPLIST_FILE = YES`, matching the v0.4.0 bump commit `95571da`)
- Sweep: grep Tasks 7–9 surfaces for any hardcoded "Set" string that bypassed `settingsManager.settings.labels.pageSet` — fix stragglers

- [ ] Sweep + bump.
- [ ] Builder (background agent): FULL `-only-testing:PommoraTests` — the feature's final green gate.
- [ ] Commit: `chore(sets): v0.4.1`

### Task 11 — Docs (final task; nothing before this)

**Files:** `.claude/CLAUDE.md`, `PommoraPRD.md`, `.claude/Framework.md`, `.claude/Features/Domain-Model.md`, `.claude/Features/PageTypes.md`, `.claude/Features/Sidebar.md`, `.claude/Features/Pages.md`, `.claude/Features/Collections.md`, `.claude/Features/Architecture.md` (on-disk layout + the "2-layer" cross-ref at L176), `.claude/Features/Properties.md` (cross-ref at L431), `.claude/History.md`, `.claude/Guidelines/Paradigm-Decisions.md`, `.claude/Planning/README.md`; **create `.claude/Features/Sets.md`** (concise present-tense feature spec — entity, sidecar, behaviors, inheritance)

Rules (per spec + docs-audit): rewrite every two-level assertion **as fact** — three-level shape stated plainly, NO "amended"/"superseded"/"previously" language in specs. `History.md` gets one brief entry: third layer (Sets) shipped at v0.4.1; `Collections.md` + `Sets.md` carry a one-line v0.4.1 note. Paradigm-decision entry records the decision and why it supersedes the Folders revert + the 2-level adoption lock. Before finishing, run a final corpus grep (`two.tier|2-layer|two layers|Page Types → Page Collections|depth`) — false positives exist (NavDropdown.md "two layers, two files", PageEditor.md ZStack layers; leave those). Move `06-11-Sets-Spec.md` + this plan to `Superseded/` per Planning convention. Minimal and precise — trim, don't append.

- [ ] Execute the rewrite; docs-audit pre-write guard per file.
- [ ] Commit: `docs(sets): three-tier operational layer recorded as fact (v0.4.1)`

---

### Review log (two stress passes, applied)

**Pass 1 (self-review):** load-order race (→ Task 4 sequential await); PageParent ripple breadth (→ full-target runs); schema bump invalidates fixtures (→ Task 2 full run); `.setOnly` delete ordering (pages move BEFORE trash); collection `pageOrder` semantics narrowing (OrderResolver tolerates orphans — verified); stub ordering (none needed); suite-name filters; detail-view data source vs load scoping (→ Task 8 concatenation).

**Pass 2 (4-agent adversarial review vs code, key corrections adopted):** NexusPaths constant lives at L12, helpers L261–297, explicit helper names; schema bump pinned 13 → 14; `PageSnapshot.setID` + `insertPage`/`upsertPage` exact signatures + three-level FK fallback order; `EntityKind`/`kindTableMap`/`FilterBuilder` mapper enumeration; `EntityContainer` fields nullable; collection-rename notification mechanism designed (`onCollectionFolderChanged` closure — none existed); PageParent ripple enumerated (15 files); `walkDepth2`/`tagDepth2IfMissing` signatures + `AdoptedSidecarKind.pageSet`; healing hoisted to shared `ContainerIDHealer` (DRY); `SidebarConfirmation.deleteSet` two-mode dialog; breadcrumb set source = router-passed parameter from `PageParent.set` (not an async lookup); detail-row concatenation order pinned (root per `pageOrder`, sets per `setOrder`, each per set `pageOrder`); "Move to…" has NO filesystem precedent — Task 9 designs it fully, borrowing only the Menu shape from the navigation-only "Move to Section"; `SettingsLabels` real shape pinned (`LabelPair`, no `defaultsVersion` bump) and moved into Task 7 where first consumed; version bump mechanics pinned (pbxproj only, matching `95571da`); docs list expanded (+ Collections.md, Architecture.md, Properties.md, new Sets.md).

**Review findings rejected after verification:** "page_sets DDL missing page_order column" — ordering is sidecar-resident by existing pattern (`page_order` appears nowhere in IndexSchema.swift); "Agenda.md/Contexts.md carry two-tier assertions" — false positives (unrelated uses of "two layers").
