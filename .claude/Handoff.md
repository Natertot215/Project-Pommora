### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-27 — `main` pushed to `origin/main` at session end)

**Session outcome: F.0 + F.1 all SHIPPED on `main` (F.1.a–F.1.k complete). F.2 (sidebar visibility) queued next. `origin/main` is in lock-step with `main`** (fast-forward push, no rewrite) so both this session and the parallel v0.3.1 Properties session operate against the same remote baseline. **Start each new session with `git pull origin main`** before doing anything else — both sessions push back to the same branch, so the remote is the canonical truth and either session can be ahead at any moment. Commits from this and the prior session on top of `0a0411a`:

| Commit | Scope |
|---|---|
| `68caf96` | **F.0** — system-wide stub-and-inline-rename CRUD refactor (no popups). Every "New X" trigger across Pommora (PageType / PageCollection / Page / ItemType / ItemCollection / Item / Space / Topic / Project) now creates immediately with a default title and auto-flips the matching sidebar row into rename mode with `selectAllOnAppear`. Deleted 9 `New*Sheet.swift` files + `SidebarSheet` cases + both `.sheet(item:)` switches. New `Pommora/CRUD/DefaultTitleResolver.swift` + `Pommora/CRUD/CreateWithInlineEdit.swift` (3 + 9 + 7 new tests). All 7 manager `create*` methods now return the new entity via `@discardableResult`. ContentView owns `editingID` + `justCreatedID` `@State`, cascaded through SidebarView's 4 sections + 8 row files AND SidebarDetailView's 4 detail views. RenameableRow gains `selectAllOnAppear` + AppKit responder hop. **811/815 tests pass.** 4 pre-existing test failures unrelated (3 are `sidebarSections.items` label drift expecting "Types" vs current "Items" seed; 1 PageEditor debounce timing flake). |
| `50a1f6f` | **F.1.a/b** — Folder model + `_folder.json` sidecar paths. `Pommora/Vaults/Folder.swift` mirrors PageCollection's shape with `collectionID` (FK to parent Collection) + `icon` (per-Folder customizable SF Symbol — divergence from Collections). Snake-case JSON keys. Custom Codable defensively decodes legacy sidecars lacking `schema_version` as `0`. `NexusPaths.folderSidecarFilename = "_folder.json"` + `folderFolderURL` + `folderMetadataURL` helpers. 5 new FolderTests pass. |
| `25c0009` | **F.1.c/d** — PageCollection.folderOrder + SQLite folders table. PageCollection gains `folderOrder: [String]?` mirroring `pageOrder` shape (`folder_order` JSON key, nil-omitted via `encodeIfPresent`, legacy decodes as nil). Both PageCollection-rebuild sites in PageTypeManager (renamePageType + renamePageCollection) preserve folderOrder alongside pageOrder. IndexSchema gains `foldersDDL` (id/page_collection_id/page_type_id/title/icon/modified_at/schema_version with CASCADE FK to both parents). `pagesDDL` extended with `page_folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL` for fresh databases. New `addPageFolderIDColumnIfMissing(db)` idempotent ALTER for legacy databases via GRDB's `db.columns(in:)`. 3 new indexes. 5 new folderOrder tests pass; 51-suite filtered run all green. |
| `77490f1` | **F.1.e/f** — IndexBuilder three-level walk + IndexQuery/IndexUpdater Folder helpers. Private `FolderSnapshot: Sendable` carried by `PageCollectionSnapshot.folders`. `PageSnapshot` gains `folderID: String?`. `collectPageTypes` walks each Collection's sub-folders for `_folder.json`, threading FK trio (page_type_id / page_collection_id / page_folder_id) through nested page inserts. `clearAllTables` adds `DELETE FROM folders` ordered correctly. `insertRelations` + `insertTierLinks` extended to cover pages-in-folders too. `TargetRef.folder(String)` for filter/sort queries. `IndexUpdater.upsertFolder(_:)` / `deleteFolder(id:)`. `upsertPage` gains optional `pageFolderID:` default nil — backward-compatible with every existing call site. 7 new IndexBuilderTests + 5 new IndexUpdaterTests + 2 new IndexQueryTests, all green. |
| `e7c6295` | **F.1.g** — PageTypeManager Folder CRUD + loadAll walk. New `foldersByCollection: [String: [Folder]]` keyed by parent Collection.id + `folders(in:)` accessor. `loadAll` walks each Collection's sub-folders for `_folder.json`, mints a default Table view via `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` on `views.isEmpty`, defensively upserts each Folder into SQLite per quirk #15. Full CRUD: `createFolder` / `renameFolder` / `updateFolderIcon` / `deleteFolder` / `reorderFolders` (mirrors PageCollection's shape line-for-line). Rename cascades: `renamePageType` + `renamePageCollection` rebuild nested Folder `folderURL`s under the new parent path. `deletePageCollection` clears `foldersByCollection` for the trashed Collection. New `FolderValidator` mirrors `PageCollectionValidator` (sibling-uniqueness scoped to parent Collection). New `OrderPersister.setFolderOrder(_:in:)`. 16 PageTypeManagerFolderCRUDTests + 6 FolderValidatorTests, all green. Zero regressions in PageTypeManagerTests / IndexBuilderTests / IndexUpdaterTests. |
| `2d0c0d3` | **F.1.h** — PageContentManager Folder content + CRUD. `pagesByFolder: [String: [PageMeta]]` keyed by `Folder.id` + `pages(in folder:)` accessor. `resolveParent` signature CHANGED from 2-tuple `(vault, collection?)` to 3-tuple `(vault, collection?, folder?)` — both existing call sites (`ContentView.swift:316`, `PageEditorHost.swift:93-99`) read by field name so compile-clean. `loadAll(for: collection)` excludes Folder-tagged sub-folders. New `loadAll(for: folder:)`. Full Folder-scoped CRUD overloads in `+CRUD.swift`: `createPage` / `renamePage` / `deletePage` / `updatePage` (each `in folder:Folder, vault:PageType`) routing the FK trio through `upsertPage(pageFolderID: folder.id)`. New `reorderPages(in folder:fromOffsets:toOffset:)` persisting via new `OrderPersister.setPageOrder(_:in folder:)` against `Folder.pageOrder`. 11 PageContentManagerFolderTests, all green; 110-unique-test sweep across PageContent/PageType/IndexBuilder/IndexUpdater/IndexQuery/Folder suites also green. |
| `2404176` | **F.1.i / F.1.j / F.1.k** — NexusAdopter `.folder` + silent auto-tag + NexusManager wiring + tests. `AdoptedSidecarKind.folder` (filename → `_folder.json`); `recognizedFlatSidecarFilenames` extended; `recognizedSidecarsAt` includes `.folder` last (tier-3 precedence rule); `cleanupLegacyOrphans` walks one tier deeper; `writeFreshSidecar` switch made exhaustive on `.folder`. New public `NexusAdopter.autoTagMissingSidecars(at:)` — silent three-level walk with depth-aware kind selection (depth-0 content-sniff → `_pagetype.json` or `_itemtype.json`; depth-1 reads parent type sidecar → `_pagecollection.json` or `_itemcollection.json`; depth-2 Pages-side only → `_folder.json`; depth-2 Items-side → no-op since Items has no third tier). Skips dotfile/underscore-prefixed folder names + `adoptionExcludedSubFolderNames`. Idempotent + silent — failures logged to stderr in DEBUG, never abort launch. **NexusManager.openExisting + openPicked** call `autoTagMissingSidecars(at:)` unconditionally after `runAdoptionIfNeeded`, before `openIndex` — IndexBuilder's wipe-and-rebuild sees the fully-tagged tree. `AdoptionPreviewView.swift` `iconForSidecar` / `labelForSidecar` switches made exhaustive on `.folder` (literal "Folder" stopgap until F.5 routes through `labels.folder.singular`). New NexusAdopterAutoTagTests (3-tier round-trip, Items 2-tier-only, idempotence, dotfile/underscore exclusion, dotfile-child skip, mixed-shape only-missing). New FolderIndexSyncTests (loadAll → SQLite quirk-15 parity). **272 tests, 0 failures** across 11 suites including 56 NexusAdopter regressions. Pushed to `origin/main` (`8f7fb3d..2404176`). |

> Lint note: three pre-existing `try? Filesystem.moveToTrash(attachmentsURL, in: nexus)` lines in `+CRUD.swift` warn under current strictness (`result of 'try?' is unused`). Inherited pattern; defer to a separate sweep — not in F.1.h's intent.

#### Side-channel: parallel v0.3.1 Properties UX rebuild — in-flight in working tree

Nathan has separate in-progress edits to the property editor surfaces (`Properties/Editor/SelectOptionsEditor.swift`, `Properties/Editor/StatusGroupsEditor.swift`, `Properties/Chips/PropertyChipColor.swift`, `Properties/PropertyTypePicker.swift`, `ViewSettings/EditOptionPane.swift`, `ViewSettings/EditPropertyPane.swift`, `ViewSettings/PropertiesListPane.swift`, `ViewSettings/PropertyTypePickerPane.swift`, `ViewSettings/PropertyVisibilityPane.swift`, plus new files `ViewSettings/PropertyEditorErrorMessage.swift` + `Properties/Editor/OptionEditPopover.swift`). These are NOT in the F.0 / F.1 commits — they sit in working tree as a coherent parallel-session unit.

**API shape iterated mid-session.** `SelectOptionsEditor` / `StatusGroupsEditor` signatures changed from 1-arg `(options:)` to 4-arg `(options:propertyID:path:onAddOption:)` and then back to 2-arg `(options:onAddOption:)`. My commits never touched these editor files; my F.0 reconciled call-site patches to `Properties/TypeSettingsSheet.swift` + `Properties/VaultSettingsSheet.swift` are LIVE in working tree against the current 2-arg shape but were not committed (they pair with parallel-session work, not with F.0's intent). When Nathan ships the v0.3.1 properties work, those Settings-sheet patches should ride along.

#### Properties polish session — paused 2026-05-26 (pending Nathan review)

> Slice 1 popover iteration in working tree. **Improved but unverified.** Every theme below is provisional until Nathan smokes it.

**State:** uncommitted in working tree, compile-clean per last build. Sits alongside the F.0 + F.1.a-d Folders work but not coupled to it — commit as its own unit when ready.

**Files touched:** `Properties/Editor/{SelectOptionsEditor,StatusGroupsEditor,OptionEditPopover (NEW)}.swift`, `Properties/{PropertyTypePicker, Chips/PropertyChipColor}.swift`, `ViewSettings/{EditPropertyPane, StorageMenuRoot, PropertiesListPane, PropertyVisibilityPane, PropertyTypePickerPane, EditOptionPane, PropertyEditorErrorMessage (NEW)}.swift`, `DesignSystem/PUI.swift`. Settings-sheet patches in `Properties/{VaultSettingsSheet,TypeSettingsSheet}.swift` ride along.

**Themes (provisional — pending smoke):**

- Inline `OptionEditPopover` (double-click on chip) replaces chevron-push for option editing.
- Pill backgrounds on title TextFields + icon Buttons via `Color.primary.opacity(0.06)`.
- Bare `Menu` (`.menuStyle(.borderlessButton)`) replaces `.pickerStyle(.menu)` for inline selectors.
- Delete + Duplicate moved INSIDE the EditPropertyPane scroll body; dividers inset.
- Snapshot→live binding refactor in `PropertiesListPane` + `PropertyVisibilityPane`.
- Section labels at `.headline`; `PUI.Icon.header` at `.title3` / frame 28pt.
- SymbolPicker constrained to 540×460 popover (both pane + sheet entry points).

**Slice 2/3 backlog — NOT started:**

1. **Doubled "Done" in cell editor.** Render `Menu` directly from Status/Select/MultiSelect Table cells; skip `PropertyCellEditor`'s popover wrapper. File: `Detail/Columns/PropertyCellEditor.swift`.
2. **Column drag-reorder.** macOS 14+ `TableColumnCustomization` + `.customizationID(...)` per column in all four detail views; persist to `view.visibleProperties` via `updateView()`. Confirm public order accessor; ship session-only first if API gates persistence.
3. **Snapshot→live for `userPropertyColumns`** in all four detail views — re-query manager by stable type ID instead of reading from the `pageType` snapshot.

**Why paused:** `OptionEditPopover` alignment loop ate time. Paused for focus + documentation before detail-view work.

**Open UIX questions (smoke-needed):** popover rail alignment at sub-pixel level, `StorageMenuRoot` vs `EditPropertyPane` pill parity, SymbolPicker 540×460 visual feel, `.headline` section labels relative to chip text, `+ Add` row tap-target size.

**Discipline (continues, unchanged):** STOP-and-ASK on uncertainty • audit by reading actual files before claiming complete • in-line code only for frontend (background `building-apple-platform-products` agent for build verify) • Auto Mode OFF • match design references exactly • derive measurements from math.

**Reference:** principles captured in `.claude/Guidelines/Design.md` (Liquid Glass continuity + Context-aware padding sections).

**Resume:** continue Slice 2/3 backlog with same discipline. Coordinate with the F-series session before touching `Pommora/Vaults/`, `Pommora/Index/`, `Pommora/Nexus/`, or `Pommora/Content/`.

#### Locked decisions this session (F.0 paradigm-affecting)

1. **Esc on a freshly-stubbed entity leaves it created.** Sidecar literally named "New Folder" / "New Collection 2" / etc. stays on disk until user renames or deletes via context menu. No delete-on-cancel.
2. **TextField select-all-on-fresh-stub only.** When a row enters rename mode because it was just stub-created (`justCreatedID == entity.id`), the entire default title is pre-selected so first keystroke replaces it. Existing rename-from-context-menu keeps cursor-at-end.
3. **`isCreating` flag guards rapid double-clicks** at every trigger site. Disabling the button/menu item while a create Task is in flight prevents collision toasts from the default-title disambiguator.
4. **Context-tier in scope of F.0** (Space / Topic / Project) — plan's "every New X" prose interpreted as system-wide; explicit list expanded to 9 entities total.
5. **Detail-view footer "+" buttons drive sidebar rename mode** by sharing `editingID` + `justCreatedID` bindings via ContentView (lifted from SidebarView's local @State).
6. **Manager `create*` methods return their new entity** via `@discardableResult` — backward-compatible with existing call sites; coordinator reads the new id for the editingID flip.

#### Locked decisions prior session — Folders + CRUD (carry forward, applied in F.1)

1. **Folders have customizable per-Folder icons** (divergence from Collections, which use hardcoded `folder` symbol). Icon picker reuses SymbolPicker like Page Types + Topics. *(applied in F.1.a — Folder.icon is `String?`)*
2. **Pages coexist at Collection root with Folders** (mirrors how Pages already live at PageType root alongside Collections). *(applied in F.1.c — PageCollection now carries both `pageOrder` for root Pages and `folderOrder` for Folders)*
3. **Folders inherit property schema from grandparent Page Type** (mirror Collections — no per-Folder schema override at v1). *(applied in F.1.a — Folder has no `properties` field)*
4. **Fresh Folder views start cold** — `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` minted on creation. Does NOT copy parent Collection's current view. *(deferred to F.1.g — PageTypeManager.createFolder will mint this)*
5. **Folder view-state is independent + individually editable** — `views: [SavedView]` on Folder behaves like Collection's `views[]`, edited per-Folder via the View Settings popover at a new `ViewSettingsScope.folder(Folder)` case. *(applied in F.1.a — Folder.views; ViewSettingsScope.folder lands in F.4)*
6. **NO `hidden: Bool` on Folder** (REVERSAL — was added mid-session, then removed). Per-view property column visibility lives inside `views[0].hiddenProperties` as today. Whole-Folder hide-from-sidebar is a Prospect.
7. **Cross-container Page moves go through a nested "Move to ▸" context-menu submenu** — NOT a modal sheet, NOT sidebar drag. Drag stays for same-zone reorder only.
8. **All "New X" CRUD triggers system-wide switch to stub-and-inline-rename** — no modal sheets. **SHIPPED in F.0.**
9. **Folder sidecar = `_folder.json`** (NOT `_collectionfolder.json`). Swift type = `Folder`. SQLite table = `folders`. FK column on pages = `page_folder_id`. **SHIPPED in F.1.a/d.**
10. **NexusAdopter extends to Folder tier** — `AdoptedSidecarKind.folder` added; recognized-sidecar set extended; legacy-orphan cleanup walks one tier deeper. *(deferred to F.1.i)*
11. **Auto-sidecar-tagging on every launch (silent, paradigm shift)** — new `NexusAdopter.autoTagMissingSidecars(at:)` walks the Nexus root three levels deep on every launch and silently writes missing `_pagetype.json` / `_pagecollection.json` / `_folder.json` so users can build structure entirely via Finder. *(deferred to F.1.i)*
12. **Implementation done in-line by Claude — no code-writing delegated to subagents.** Build verification via background `building-apple-platform-products` agent per quirk #14 is the only carve-out (focus-theft mitigation, not code delegation). **HONORED THIS SESSION.**

#### What's next (F.1.h completion onwards)

The remaining F.1 slices are queued in priority order. Each ships green independently and can be committed as its own slice:

- **F.1.h — PageContentManager pages-in-folders.** ✅ SHIPPED this session.
- **F.1.i — NexusAdopter `.folder` + silent auto-tagging paradigm shift.** ✅ SHIPPED this session.
- **F.1.j — NexusManager launch-flow wiring.** ✅ SHIPPED this session.
- **F.1.k — F.1 verify (NexusAdopterAutoTagTests + FolderIndexSyncTests).** ✅ SHIPPED this session.

**F.2 (Folder sidebar visibility)** is next — adds `FolderRow.swift`, `SelectionTag.folder`, `SidebarSelection.folder`, `EntityStateRef.Kind.folder` for Pinned support. `PageCollectionRow` extended with `CollectionChildItem` enum (Folder + Page children). Then F.3 (Folder CRUD UI using F.0 stub-and-edit), F.4 (FolderDetailView + ViewSettingsScope.folder binding — collides with parallel v0.3.1 Properties work in `ViewSettings/`; coordinate before starting), F.5 (documentation accuracy pass + `labels.folder.singular` wire-up replacing the AdoptionPreviewView literal stopgap).

#### Parallel-session coordination note

**The v0.3.1 Properties UX rebuild work in `Pommora/Properties/Editor/*`, `Pommora/Properties/Chips/*`, `Pommora/Properties/PropertyTypePicker.swift`, and `Pommora/ViewSettings/*` is uncommitted in working tree** as of session end. The settings-sheet call-site patches I wrote to keep the build green (matching whatever editor signature is current) are also uncommitted. When Nathan finishes the Properties rebuild, those patches need to ride along with that commit (not with future F-series commits).

**F.4 will collide with the Properties rebuild work** — `ViewSettingsScope.folder(Folder)` lives in `StorageMenuRoot.swift` which is in `ViewSettings/`. Coordinate before starting F.4.

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **F.0 + F.1 (a–k) fully SHIPPED on `main`. `origin/main` in sync.** Folder data layer is complete end-to-end: model + sidecar + SQLite schema + IndexBuilder three-level walk + IndexQuery/IndexUpdater Folder helpers + PageTypeManager Folder CRUD + PageContentManager Folder content CRUD + NexusAdopter silent auto-tag paradigm shift + NexusManager launch-flow wiring + comprehensive tests (272 unique passing across 11 suites). **Next: F.2 — Folder sidebar visibility.** Adds `FolderRow.swift` (mirror `PageCollectionRow.swift` shape, disclosure parent), `SelectionTag.folder(String)`, `SidebarSelection.folder(Folder)`, `EntityStateRef.Kind.folder` for Pinned support, `PageCollectionRow` extended with `CollectionChildItem` enum (Folder + Page children render in one ForEach + one onMove; intra-group reorder only). Then F.3 (Folder CRUD UI using F.0 stub-and-edit coordinator — `New Folder` context menu on Collection row), F.4 (`FolderDetailView` mirror of `PageCollectionDetailView` + `ViewSettingsScope.folder(Folder)` — **this collides with parallel v0.3.1 Properties work in `ViewSettings/StorageMenuRoot.swift`; coordinate before starting**), F.5 (documentation accuracy pass: sweep `Features/{PageTypes,Pages,Collections}.md`, `Sidebar.md`, `Domain-Model.md`, `PommoraPRD.md` for 'two-layer'/'Vault + Collection only' language + add brief `Features/Folders.md` ~80-120 lines + add `folder: LabelPair` to SettingsLabels with defensive `init(from:)` that replaces the `AdoptionPreviewView.swift` literal 'Folder' stopgap at `labelForSidecar(_:)`). **DO NOT touch** `Pommora/Properties/*` or `Pommora/ViewSettings/*` (parallel v0.3.1 work in working tree). Approved plan at `.claude/Planning/2026-05-26-folders-and-stub-crud-refactor-plan.md`."

#### Locked rules from the Properties rebuild (durable — schema, correctness, workflow)

> UIX-specific design choices that may change (type picker layout, drag affordances, gesture canonicalization, design-tool workflow) have been removed from this list. They live in the active plan + working code until smoke-verified and locked.

1. **Property Visibility shows ONLY user properties + `_modified_at`.** Reserved IDs (`_id`, `_created_at`, `_status`, `_tier1/2/3`, `_wikilinks`) do not appear in the user-facing visibility list. Schema-level decision.
2. **Error display uses user-friendly sentences.** Raw enum descriptions (`String(describing: error)`) banned. Errors clear on every fresh user input.
3. **All popover-side surfaces MUST read live from the manager via stable IDs.** Never from captured `ViewSettingsScope` payloads. Property-pane equivalent of quirk #16 (env re-injection).
4. **STOP-and-ASK on uncertainty.** Any uncertainty about interaction model, UX flow, design specifics, gesture behavior, error-state copy, drop-target affordances, or animation behavior → stop and ask Nathan. No guessing.

> Folders + CRUD locked decisions (carry-forward from the queued plan) are listed once above under "Locked decisions prior session — Folders + CRUD"; not re-listed here.

#### Plan structure (phases)

- **F.0 — CRUD refactor (pre-work, ships independently).** Add `CreateWithInlineEdit.swift` + `DefaultTitleResolver.swift`. Convert PageType, PageCollection, Page, ItemType, ItemCollection, Item creation paths. Delete all `New*Sheet.swift` files + their `SidebarSheet` cases. Move validators from sheet-driven to commit-driven (rename-path).
- **F.1 — Folder schema + model + adopter + auto-tag.** `Folder.swift`, `_folder.json` sidecar, GRDB migration (`folders` table + `page_folder_id` column with `.immediate` FK checks), IndexBuilder three-level walk, `NexusAdopter.autoTagMissingSidecars`, `NexusManager.runAdoptionIfNeeded` step 3 wiring.
- **F.2 — Folder sidebar visibility.** `FolderRow.swift`, `SelectionTag.folder`, `SidebarSelection.folder`, `EntityStateRef.Kind.folder` for Pinned support. `PageCollectionRow` extended with `CollectionChildItem` enum (Folder + Page children).
- **F.3 — Folder CRUD (uses F.0 stub-and-edit).** "New Folder" via the shared coordinator. Rename / delete / reorder via existing CRUD-pattern infrastructure.
- **F.4 — Folder detail view + View Settings popover binding.** `FolderDetailView.swift` (mirrors `PageCollectionDetailView`). `ViewSettingsScope.folder(Folder)` case. Property Visibility / Sort / Filter / Group panes bind to Folder's `views[0]`.
- **F.5 — Documentation + Settings labels.** Add `folder: LabelPair` to `SettingsLabels` with defensive `init(from:)`. Update `CRUD-Patterns.md` to reflect new stub-and-edit pattern. Add paradigm decision entries for #11 (auto-tag) and #8 (stub-and-edit replaces sheets). **Documentation accuracy pass:** the existing `.claude/Features/{PageTypes,Pages,Collections}.md` describe the model as Vault + Collection only — sweep each file and update language to reflect Vault → Collection → **Folder** → Page as the canonical three-tier shape on the Pages side. Remove every "two-layer" / "Vault + Collection only" / "Vaults and Collections" phrasing that contradicts the new tier. Also touch `Sidebar.md` (three-level row vocabulary), `Domain-Model.md` (Pages-side three-layer note), and `.claude/PommoraPRD.md` (a quick note acknowledging Folders as the third tier on the Pages side; storage-model + architecture sections must not assume only two layers). **Add `.claude/Features/Folders.md`** — keep it BRIEF and concise (target ~80–120 lines): on-disk shape (`_folder.json`), per-Folder icon divergence from Collections, fresh-Folder cold-start view seed, schema inheritance from grandparent PageType, three-layer cap (no nested Folders / no Collections inside Folders), `folder_order` on parent Collection, sidebar + detail-view behavior, "Move to ▸" context-menu submenu for cross-container moves. Cross-link to `PageTypes.md` + `Pages.md` rather than duplicating their content.

#### Critical implementation notes

- **GRDB v7 migration syntax** uses the builder (`db.create(table:)`, `db.alter(table:)`, `.references("table", onDelete: .setNull)`), NOT raw SQL. Use `foreignKeyChecks: .immediate` for the schema-only Folders migration per GRDB best practice (avoids temporary FK disable cycle).
- **IndexBuilder strategy is DELETE-then-repopulate** ([IndexBuilder.swift:125–149](Pommora/Pommora/Index/IndexBuilder.swift#L125-L149)) — no post-migration backfill needed. The migration adds the empty `folders` table; the next IndexBuilder.populate wipes everything and rebuilds with the now-fully-tagged tree.
- **PageCollection.swift gains `folderOrder: [String]?`** alongside existing `pageOrder: [String]?` (mirrors how PageType has both `collectionOrder` and `pageOrder` for coexisting child kinds). JSON key `folder_order`. Drag-reorder is intra-group only — Folders reorder among Folders, Pages among Pages, never mixed.
- **SettingsLabels needs a custom `init(from:)`** to defensively decode the new `folder` field (`decodeIfPresent ?? defaults().folder`). The struct currently uses auto-synthesized Codable which would crash on legacy settings.json files.
- **Cross-Folder move is NOT supported at v1** — Folders are structurally fixed to their parent Collection. Relocate by deleting and recreating, or Finder-move + let next launch's auto-tag re-classify. First-class Folder relocation is a Prospect.

#### Folders + CRUD: queued state

Plan at `.claude/Planning/2026-05-26-folders-and-stub-crud-refactor-plan.md` remains approved. Resume after Properties Slice 1 ships green.

- **Phase F.0 survey step** was `in_progress`. To resume: read `PageCollectionRow.swift`, `RenameableRow.swift`, `NewPageCollectionSheet.swift`, `SidebarSheet.swift`, and `PageTypeManager.createPageCollection` to lock down the existing pattern being replaced.
- **Then create shared utilities:** `Pommora/Pommora/CRUD/DefaultTitleResolver.swift` + `Pommora/Pommora/CRUD/CreateWithInlineEdit.swift`.
- **Then migrate entity-by-entity:** PageCollection → PageType → Page → ItemType → ItemCollection → Item, green-commit each.
- After F.0 ships green: proceed to F.1 (Folder schema + model + adopter + auto-tag) per the plan.

#### Locked decisions in force (carry forward from prior sessions)

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.**
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1/2/3`, `_wikilinks`. User-defined mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.**
5. **`PropertyIDMigration` runs on EVERY nexus open** — idempotent.
6. **tier1/2/3 are root-level frontmatter fields** (not under `properties:`).
7. **AgendaTask + AgendaEvent default seed = single `_status` property.**
8. **`DualRelationCoordinator` owns paired-relation lifecycle.**
9. **`AttachmentManager` is the only path for file values.**
10. **Settings carries `defaultsVersion: Int`** bumped to v2 on 2026-05-25.
11. **Items + Pages are NOT renameable concepts** — only containers are (Vault / Collection / Type / Set / Folder).
12. **View Settings button = single static instance at ContentView level inside the existing primary-action `.glassEffect()` HStack.**
13. **`PUI` design tokens** — single source of truth for paddings / spacings / icons / fonts / radii. Forbidden in new code: magic-number padding. Extend `Pommora/Pommora/DesignSystem/PUI.swift` rather than inlining raw values.
14. **`PaneHeader` is the chrome for every View Settings sub-pane** — no `.navigationTitle(_:)` allowed on pushed panes.
15. **`SidebarSelection` no longer reads `AppGlobals`** — all selection resolution goes through `SidebarLookupBundle`. AppGlobals is forbidden as a selection-resolution source.
16. **Popover-side surfaces read live from the manager via stable IDs.** `PropertiesListPane`, `EditPropertyPane`, `PropertyVisibilityPane`, `EditOptionPane` must NEVER read state from captured `ViewSettingsScope` payloads — always look up via type ID / property ID / option value from the live manager. View-state propagation equivalent of quirk #16 (env re-injection).
17. **Visibility lists show ONLY user properties + `_modified_at`.** Reserved IDs are filtered out — they have no place in a user-facing visibility list.

#### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include.
3. **Trust `xcodebuild`, not SourceKit squiggles.**
4. **`.claude/*` is included in commits.**
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`.
6. *(retired in ParadigmV2)*
7. **Xcode auto-reorders SymbolPicker/Yams/GRDB entries in pbxproj on every build** — incidental noop diff. Revert before commit.
8. **Stub-and-progressively-replace** is the locked execution strategy.
9. **Section structure in SidebarView is load-bearing.** Don't break `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`).
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. **This session reaffirmed: code-writing in-line by Claude; xcodebuild verification via background Agent.**
14. **GRDB `String` overload pollution in @ViewBuilder closures** — isolate per-row rendering into private struct sub-views.
15. **`loadAll` must sync in-memory parents to the SQLite index.** Defensive INSERT OR REPLACE upserts after disk load. Critical for the Folders work — `PageTypeManager.loadAll` must also defensively upsert the new `foldersByCollection` entries.
16. **Every `@Environment(X.self)` declared on a detail view OR popover-hosted view must be explicitly re-injected at the boundary.** When adding `FolderDetailView` in F.4, every env it declares must also be in `ContentView.detail`'s `.environment(...)` chain (~line 237).
17. **`Button(role: .close) { dismiss() }` without an explicit `label:` closure crashes outside `.toolbar { ... }` context.**
18. **(NEW this session)** **STOP-and-ASK on uncertainty.** Any uncertainty about interaction model, UX flow, design specifics, gesture behavior, error-state copy, drop-target affordances, or animation behavior → stop implementing and ask Nathan. No guessing, no "I'll pick something reasonable." Lesson from the v0.3.1 slice-execution drift.
19. **(NEW this session)** **Zero subagents for any frontend-touching work.** All SwiftUI / view-layer code is written in-line by Claude. Applies across Slices 1, 2, AND 3 of the Properties rebuild — every step touching the View Settings popover, EditPropertyPane, EditOptionPane, options editors, PropertyVisibilityPane, PropertyTypePicker, detail-view Table columns, cell editor popovers, or any other UI surface. Permitted carve-outs: read-only Explore agents for code-survey; `building-apple-platform-products` background xcodebuild runs per #14 (verification only, no code-writing). The Folders + CRUD plan's "code-writing in-line by Claude — no code-writing delegated to subagents" rule (locked decision #12 from prior session) generalizes to this scope.

#### Properties rebuild scope summary

Beyond Slice 1 (above), the rebuild plan covers:

- **Slice 2 — v0.3.1.1 "Dynamic columns in detail views."** Build `updatePageProperty(...)` + `updateItemProperty(...)` atomic single-property writes. Build `PropertyColumnBuilder` + `PropertyCellDisplay` using existing chip primitives. Wire all 4 detail views.
- **Slice 3 — v0.3.1.2 "Click-to-edit cell popovers."** Build `PropertyCellEditor` wrapper. Wire 11 per-type editor popovers (reuse PropertyEditorRow dispatcher). Patch PropertyEditorRow relation / status / file stubs to real editors.

Items NOT in the three-slice scope (still queued for follow-up):

- Simple-type inline anchored popover split (Number / URL / Checkbox / File) — may not be needed if Slice 3's universal popover model proves clean.
- Date & Time consolidation (drop `.date`, keep only `.dateTime`).
- Relation editor full redesign (searchable target picker + Show on [target] toggle + mirror name + Limit) — after Slice 3 ships.
- StorageMenuRoot 8-row redesign (inline-edit Vault/View title rows) — only after Slice 3, with Figma in the loop.
- `@FocusState` click-outside-commits — small fix; can piggyback on any slice.
- Sidebar / detail-view chrome PUI migration — separate concern, not blocking property work.

All deferred items get their own focused plan documents after Slice 3 ships green.

#### Document pointers

- **Active plan (Properties rebuild)**: `.claude/Planning/2026-05-26-v0.3.1-properties-rebuild-plan.md`
- **Queued plan (Folders + CRUD)**: `.claude/Planning/2026-05-26-folders-and-stub-crud-refactor-plan.md`
- **Superseded plan (v0.3.1 original)**: `.claude/Planning/Superseded/2026-05-26-View-Settings-edit-properties-plan-COMPLETE.md` — referenced by the rebuild plan for UIX detail recovery
- **Roadmap (chronological)**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Per-entity specs**: `.claude/Features/{Domain-Model, Contexts, PageTypes, Pages, Items, Agenda, Homepage, NavDropdown, Sidebar, PageEditor, Architecture, Prospects}.md`
- **CRUD pattern (will change in Folders + CRUD F.0)**: `.claude/Guidelines/CRUD-Patterns.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **Figma source for property editor**: `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`

