### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-26 — `main` at `25c0009`, +40 commits ahead of `origin/main`)

**Session outcome: F.0 system-wide stub-and-inline-rename CRUD refactor SHIPPED, plus F.1.a–F.1.d (Folder model + sidecar + PageCollection.folderOrder + SQLite schema) SHIPPED.** Three commits landed this session on top of `0a0411a`:

| Commit | Scope |
|---|---|
| `68caf96` | **F.0** — system-wide stub-and-inline-rename CRUD refactor (no popups). Every "New X" trigger across Pommora (PageType / PageCollection / Page / ItemType / ItemCollection / Item / Space / Topic / Project) now creates immediately with a default title and auto-flips the matching sidebar row into rename mode with `selectAllOnAppear`. Deleted 9 `New*Sheet.swift` files + `SidebarSheet` cases + both `.sheet(item:)` switches. New `Pommora/CRUD/DefaultTitleResolver.swift` + `Pommora/CRUD/CreateWithInlineEdit.swift` (3 + 9 + 7 new tests). All 7 manager `create*` methods now return the new entity via `@discardableResult`. ContentView owns `editingID` + `justCreatedID` `@State`, cascaded through SidebarView's 4 sections + 8 row files AND SidebarDetailView's 4 detail views. RenameableRow gains `selectAllOnAppear` + AppKit responder hop. **811/815 tests pass.** 4 pre-existing test failures unrelated (3 are `sidebarSections.items` label drift expecting "Types" vs current "Items" seed; 1 PageEditor debounce timing flake). |
| `50a1f6f` | **F.1.a/b** — Folder model + `_folder.json` sidecar paths. `Pommora/Vaults/Folder.swift` mirrors PageCollection's shape with `collectionID` (FK to parent Collection) + `icon` (per-Folder customizable SF Symbol — divergence from Collections). Snake-case JSON keys. Custom Codable defensively decodes legacy sidecars lacking `schema_version` as `0`. `NexusPaths.folderSidecarFilename = "_folder.json"` + `folderFolderURL` + `folderMetadataURL` helpers. 5 new FolderTests pass. |
| `25c0009` | **F.1.c/d** — PageCollection.folderOrder + SQLite folders table. PageCollection gains `folderOrder: [String]?` mirroring `pageOrder` shape (`folder_order` JSON key, nil-omitted via `encodeIfPresent`, legacy decodes as nil). Both PageCollection-rebuild sites in PageTypeManager (renamePageType + renamePageCollection) preserve folderOrder alongside pageOrder. IndexSchema gains `foldersDDL` (id/page_collection_id/page_type_id/title/icon/modified_at/schema_version with CASCADE FK to both parents). `pagesDDL` extended with `page_folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL` for fresh databases. New `addPageFolderIDColumnIfMissing(db)` idempotent ALTER for legacy databases via GRDB's `db.columns(in:)`. 3 new indexes. 5 new folderOrder tests pass; 51-suite filtered run all green. |

#### Side-channel: parallel v0.3.1 Properties UX rebuild — in-flight in working tree

Nathan has separate in-progress edits to the property editor surfaces (`Properties/Editor/SelectOptionsEditor.swift`, `Properties/Editor/StatusGroupsEditor.swift`, `Properties/Chips/PropertyChipColor.swift`, `Properties/PropertyTypePicker.swift`, `ViewSettings/EditOptionPane.swift`, `ViewSettings/EditPropertyPane.swift`, `ViewSettings/PropertiesListPane.swift`, `ViewSettings/PropertyTypePickerPane.swift`, `ViewSettings/PropertyVisibilityPane.swift`, plus new file `ViewSettings/PropertyEditorErrorMessage.swift`). These are NOT in the F.0 / F.1 commits — they sit in working tree as a coherent parallel-session unit.

**API shape iterated mid-session.** `SelectOptionsEditor` / `StatusGroupsEditor` signatures changed from 1-arg `(options:)` to 4-arg `(options:propertyID:path:onAddOption:)` and then back to 2-arg `(options:onAddOption:)`. My commits never touched these editor files; my F.0 reconciled call-site patches to `Properties/TypeSettingsSheet.swift` + `Properties/VaultSettingsSheet.swift` are LIVE in working tree against the current 2-arg shape but were not committed (they pair with parallel-session work, not with F.0's intent). When Nathan ships the v0.3.1 properties work, those Settings-sheet patches should ride along.

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

#### What's next (F.1.e onwards — clean resume points)

The remaining F.1 slices are queued in priority order. Each ships green independently and can be committed as its own slice:

- **F.1.e — IndexBuilder three-level walk + FolderSnapshot.** `Pommora/Pommora/Index/IndexBuilder.swift`. Add `FolderSnapshot: Sendable` private struct. Extend `PageCollectionSnapshot` to carry `folders: [FolderSnapshot]`. Extend `PageSnapshot` with `folderID: String?`. Extend `collectPageTypes(from:)` (lines 166–209) to walk each Collection's sub-folders for `_folder.json` and emit FolderSnapshots. Extend `collectPagesInFolder` (lines 211–232) with nullable `folderID` parameter so Pages-inside-Folders thread the right FK trio. `clearAllTables` (lines 403–416) gains `DELETE FROM folders` ordered correctly relative to pages. `insertPageTypes` (lines 418–444) gains nested folder insert + page-inside-folder insert. `insertPage` (lines 446–454) writes `page_folder_id`.
- **F.1.f — IndexQuery + IndexUpdater.** `Pommora/Pommora/Index/IndexQuery.swift`: new `.folder(folderID)` scope returning `SELECT id, title FROM pages WHERE page_folder_id = ?`. `Pommora/Pommora/Index/IndexUpdater.swift`: new `upsertFolder(_ folder: Folder)` + `deleteFolder(id: String)` helpers + `upsertPage` extended to accept optional `pageFolderID:` for routing.
- **F.1.g — PageTypeManager folders.** `Pommora/Pommora/Vaults/PageTypeManager.swift`. Add `private(set) var foldersByCollection: [String: [Folder]] = [:]` + `func folders(in collection: PageCollection) -> [Folder]`. Extend `loadAll` (lines 31–146) to walk each Collection's sub-folders for `_folder.json` + apply default-view migration (mint `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` on `views.isEmpty`) + defensively upsert per quirk #15. Add CRUD: `createFolder(in:title:)` (returns Folder, mirrors `createPageCollection` shape line-for-line), `renameFolder(_:to:)`, `deleteFolder(_:)`, `reorderFolders(in:_:)`. Mints default Table view on creation.
- **F.1.h — PageContentManager pages-in-folders.** `Pommora/Pommora/Content/PageContentManager.swift`. Add `private(set) var pagesByFolder: [String: [PageMeta]] = [:]` + `func pages(in folder: Folder) -> [PageMeta]`. Extend the load walk to detect `_folder.json` parent sub-folders and route Pages into `pagesByFolder` instead of `pagesByCollection`. `resolveParent(for:)` (lines 70–86) gains a third lookup layer. `Pommora/Pommora/Content/PageContentManager+CRUD.swift`: add a `folder: Folder?` parameter on the page-creation path (default `nil`). When set, write target is the Folder's `folderURL`, SQLite upsert fills `page_folder_id` + `page_collection_id` + `page_type_id`.
- **F.1.i — NexusAdopter + auto-tagging (paradigm shift).** `Pommora/Pommora/Nexus/NexusAdopter.swift`. Depth extension: `AdoptedSidecarKind.folder` case (filename → `folderSidecarFilename`); recognized-sidecar set at lines 260–267 gains `_folder.json`; legacy-orphan cleanup pass at lines 808–819 walks one tier deeper. New method `autoTagMissingSidecars(at: nexusRoot)` walks the Nexus root three levels deep on every launch and silently writes missing per-kind sidecars. Idempotent + silent. Skips dotfile-prefixed + underscore-prefixed folder names. Depth-aware kind selection: depth 0 unknown → content-sniff via existing `contentSniff` (lines 527–549) → `_pagetype.json` (md descendants) or `_itemtype.json` (json descendants); depth 1 inside `_pagetype.json` parent → write `_pagecollection.json`; depth 1 inside `_itemtype.json` parent → write `_itemcollection.json`; depth 2 inside `_pagecollection.json` parent → write `_folder.json`; depth 2 inside `_itemcollection.json` parent → no-op (Items has no third tier). Overrides the prior "non-Pommora folders at root stay invisible to discovery" decision at [NexusAdopter.swift:199–202](Pommora/Pommora/Nexus/NexusAdopter.swift#L199-L202). Log as next numbered entry in `.claude/Guidelines/Paradigm-Decisions.md`.
- **F.1.j — NexusManager launch flow.** `Pommora/Pommora/Nexus/NexusManager.swift`. `runAdoptionIfNeeded` (lines 268–329) gains step 3: call `NexusAdopter.autoTagMissingSidecars(at: nexusRoot)` unconditionally after the legacy `apply(plan)` pass completes. Runs before `openIndex` so IndexBuilder sees the fully-tagged tree.
- **F.1.k — F.1 verify.** Full PommoraTests run. Add `NexusAdopter+AutoTagTests.swift` (Finder-built three-tier round-trip + idempotence + dotfile/underscore exclusion). Add `FolderIndexSyncTests.swift` (loadAll → SQLite parity per quirk #15). Add `PageTypeManager+FolderCRUDTests.swift` (create / rename / delete / reorder).

After F.1 ships green, **F.2 (Folder sidebar visibility)** is next — adds `FolderRow.swift`, `SelectionTag.folder`, `SidebarSelection.folder`, `EntityStateRef.Kind.folder` for Pinned support. `PageCollectionRow` extended with `CollectionChildItem` enum (Folder + Page children).

#### Parallel-session coordination note

**The v0.3.1 Properties UX rebuild work in `Pommora/Properties/Editor/*`, `Pommora/Properties/Chips/*`, `Pommora/Properties/PropertyTypePicker.swift`, and `Pommora/ViewSettings/*` is uncommitted in working tree** as of session end. The settings-sheet call-site patches I wrote to keep the build green (matching whatever editor signature is current) are also uncommitted. When Nathan finishes the Properties rebuild, those patches need to ride along with that commit (not with future F-series commits).

**F.4 will collide with the Properties rebuild work** — `ViewSettingsScope.folder(Folder)` lives in `StorageMenuRoot.swift` which is in `ViewSettings/`. Coordinate before starting F.4.

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **`main` at `25c0009`, +40 commits ahead of `origin/main`.** Last session shipped F.0 (system-wide stub-and-inline-rename CRUD refactor, no more `New*Sheet.swift` popups) + F.1.a/b (Folder model + `_folder.json` NexusPaths) + F.1.c/d (PageCollection.folderOrder + SQLite folders table). **Next is F.1.e — IndexBuilder three-level walk + FolderSnapshot.** Read [IndexBuilder.swift](Pommora/Pommora/Index/IndexBuilder.swift) first (specifically `collectPageTypes(from:)` at lines 166–209, `collectPagesInFolder` at 211–232, `clearAllTables` at 403–416, `insertPageTypes` at 418–444, `insertPage` at 446–454). Add `FolderSnapshot: Sendable`. Extend `PageCollectionSnapshot` with `folders: [FolderSnapshot]`. Extend `PageSnapshot` with `folderID: String?`. Thread the FK trio (page_type_id / page_collection_id / page_folder_id) through inserts. **DO NOT touch** `Pommora/Properties/*` or `Pommora/ViewSettings/*` — those are Nathan's parallel v0.3.1 work in working tree. The settings-sheet call-site patches that keep the build green are ALSO uncommitted; expect to update them if Nathan iterates on the editor signature again (currently 2-arg `(options:onAddOption:)`). After F.1.e–F.1.k ship green, F.2 (sidebar visibility) is next. Approved plan at `.claude/Planning/2026-05-26-folders-and-stub-crud-refactor-plan.md`."

#### Locked decisions this session — Properties rebuild (paradigm-affecting)

1. **Type picker is a vertical LIST, not a gallery.** Icon + name per row, no description blurbs. Replaces the current `LazyVGrid` at `PropertyTypePicker.swift:94`.
2. **NO drag handles anywhere.** No `line.3.horizontal` icons, no "drag grip" affordance. Drag is initiated by direct touch/input on the row body. Applies to: SelectOptionsEditor option rows, StatusGroupsEditor option rows, PropertyVisibilityPane property rows, and any future reorderable list.
3. **Property Visibility shows ONLY user properties + `_modified_at`.** Reserved IDs (`_id`, `_created_at`, `_status`, `_tier1/2/3`, `_wikilinks`) do not appear.
4. **Error display uses user-friendly sentences.** Raw enum descriptions (`String(describing: error)`) banned. Errors clear on every fresh user input.
5. **All popover-side surfaces MUST read live from the manager via stable IDs.** Never from captured `ViewSettingsScope` payloads. This is the property-pane equivalent of quirk #16 (re-inject env at every boundary). Will land in Guidelines/CRUD-Patterns.md as a locked rule after Slice 1 ships.
6. **Relation creation in the popover wires through `RelationPropertyWizard`.** Tapping Relation pushes the existing wizard into the popover NavigationStack; on complete, auto-routes to EditPropertyPane for the new Relation property.
7. **Status drag-between-groups is the canonical group-change mechanism.** Dragging an option from one group section to another changes its `group_id` (Properties.md "Move an option between groups" mutation). Confirmation dialog lists affected entity count on drop into a different group.
8. **STOP-and-ASK is the hardest execution rule for Slice 1.** Any uncertainty about interaction model, UX flow, design specifics, gesture behavior, error-state copy, drop-target affordances, or animation behavior → stop and ask Nathan. No guessing. No "I'll pick something reasonable." This is the lesson from the slice-execution drift that produced the v0.3.1 mess.
9. **Figma context pulled FIRST.** Nathan selects nodes in his Figma desktop app; Claude calls `get_design_context` + `get_variable_defs` per node BEFORE any code; produces a Figma → PUI binding table for Nathan sign-off; only then implements rows. No more building off screenshots + sketches.

#### Locked decisions prior session — Folders + CRUD (still paradigm-affecting, queued)

1. **Folders have customizable per-Folder icons** (divergence from Collections, which use hardcoded `folder` symbol). Icon picker reuses SymbolPicker like Page Types + Topics.
2. **Pages coexist at Collection root with Folders** (mirrors how Pages already live at PageType root alongside Collections).
3. **Folders inherit property schema from grandparent Page Type** (mirror Collections — no per-Folder schema override at v1).
4. **Fresh Folder views start cold** — `SavedView.defaultTable(visiblePropertyIDs: parentType.properties.map(\.id))` minted on creation. Does NOT copy parent Collection's current view.
5. **Folder view-state is independent + individually editable** — `views: [SavedView]` on Folder behaves like Collection's `views[]`, edited per-Folder via the View Settings popover at a new `ViewSettingsScope.folder(Folder)` case.
6. **NO `hidden: Bool` on Folder** (REVERSAL — was added mid-session, then removed). Per-view property column visibility lives inside `views[0].hiddenProperties` as today. Whole-Folder hide-from-sidebar is a Prospect.
7. **Cross-container Page moves go through a nested "Move to ▸" context-menu submenu** — NOT a modal sheet, NOT sidebar drag. Drag stays for same-zone reorder only.
8. **All "New X" CRUD triggers system-wide switch to stub-and-inline-rename** — no modal sheets for PageType / PageCollection / Folder / Page / ItemType / ItemCollection / Item. Shared `CreateWithInlineEdit` coordinator + `DefaultTitleResolver` utility. (Overrides 2026-05-17 paradigm decision that locked sheet-driven CRUD.)
9. **Folder sidecar = `_folder.json`** (NOT `_collectionfolder.json`). Swift type = `Folder`. SQLite table = `folders`. FK column on pages = `page_folder_id`.
10. **NexusAdopter extends to Folder tier** — `AdoptedSidecarKind.folder` added; recognized-sidecar set extended; legacy-orphan cleanup walks one tier deeper.
11. **Auto-sidecar-tagging on every launch (silent, paradigm shift)** — new `NexusAdopter.autoTagMissingSidecars(at:)` walks the Nexus root three levels deep on every launch and silently writes missing `_pagetype.json` / `_pagecollection.json` / `_folder.json` so users can build structure entirely via Finder. Overrides the prior "non-Pommora folders at root stay invisible to discovery" decision at [NexusAdopter.swift:199–202](Pommora/Pommora/Nexus/NexusAdopter.swift#L199-L202). Add as next numbered entry in `.claude/Guidelines/Paradigm-Decisions.md`.
12. **Implementation done in-line by Claude — no code-writing delegated to subagents.** Build verification via background `building-apple-platform-products` agent per quirk #14 is the only carve-out (focus-theft mitigation, not code delegation).

#### Plan structure (phases)

- **F.0 — CRUD refactor (pre-work, ships independently).** Add `CreateWithInlineEdit.swift` + `DefaultTitleResolver.swift`. Convert PageType, PageCollection, Page, ItemType, ItemCollection, Item creation paths. Delete all `New*Sheet.swift` files + their `SidebarSheet` cases. Move validators from sheet-driven to commit-driven (rename-path).
- **F.1 — Folder schema + model + adopter + auto-tag.** `Folder.swift`, `_folder.json` sidecar, GRDB migration (`folders` table + `page_folder_id` column with `.immediate` FK checks), IndexBuilder three-level walk, `NexusAdopter.autoTagMissingSidecars`, `NexusManager.runAdoptionIfNeeded` step 3 wiring.
- **F.2 — Folder sidebar visibility.** `FolderRow.swift`, `SelectionTag.folder`, `SidebarSelection.folder`, `EntityStateRef.Kind.folder` for Pinned support. `PageCollectionRow` extended with `CollectionChildItem` enum (Folder + Page children).
- **F.3 — Folder CRUD (uses F.0 stub-and-edit).** "New Folder" via the shared coordinator. Rename / delete / reorder via existing CRUD-pattern infrastructure.
- **F.4 — Folder detail view + View Settings popover binding.** `FolderDetailView.swift` (mirrors `PageCollectionDetailView`). `ViewSettingsScope.folder(Folder)` case. Property Visibility / Sort / Filter / Group panes bind to Folder's `views[0]`.
- **F.5 — Documentation + Settings labels.** Update `.claude/Features/PageTypes.md`, `Pages.md`, `Sidebar.md`, `Domain-Model.md`. Add `folder: LabelPair` to `SettingsLabels` with defensive `init(from:)`. Update `CRUD-Patterns.md` to reflect new stub-and-edit pattern. Add paradigm decision entries for #11 (auto-tag) and #8 (stub-and-edit replaces sheets).

#### Critical implementation notes

- **GRDB v7 migration syntax** uses the builder (`db.create(table:)`, `db.alter(table:)`, `.references("table", onDelete: .setNull)`), NOT raw SQL. Use `foreignKeyChecks: .immediate` for the schema-only Folders migration per GRDB best practice (avoids temporary FK disable cycle).
- **IndexBuilder strategy is DELETE-then-repopulate** ([IndexBuilder.swift:125–149](Pommora/Pommora/Index/IndexBuilder.swift#L125-L149)) — no post-migration backfill needed. The migration adds the empty `folders` table; the next IndexBuilder.populate wipes everything and rebuilds with the now-fully-tagged tree.
- **PageCollection.swift gains `folderOrder: [String]?`** alongside existing `pageOrder: [String]?` (mirrors how PageType has both `collectionOrder` and `pageOrder` for coexisting child kinds). JSON key `folder_order`. Drag-reorder is intra-group only — Folders reorder among Folders, Pages among Pages, never mixed.
- **SettingsLabels needs a custom `init(from:)`** to defensively decode the new `folder` field (`decodeIfPresent ?? defaults().folder`). The struct currently uses auto-synthesized Codable which would crash on legacy settings.json files.
- **Cross-Folder move is NOT supported at v1** — Folders are structurally fixed to their parent Collection. Relocate by deleting and recreating, or Finder-move + let next launch's auto-tag re-classify. First-class Folder relocation is a Prospect.

#### What's next (concrete first moves)

**Slice 1 of the Properties rebuild — `v0.3.1.0.2 "Edit Properties actually works"`.** Full task list in `.claude/Planning/2026-05-26-v0.3.1-properties-rebuild-plan.md` (Slice 1 section).

1. **Pull Figma context FIRST.** Nathan selects in his Figma desktop app: EditPropertyPane root, EditOptionPane root, chip+chevron option-row variant, type-picker list row, PropertyVisibilityPane row. Claude calls `mcp__claude_ai_Figma__get_design_context` + `mcp__claude_ai_Figma__get_variable_defs` per node. Produce a Figma → PUI binding table. **Nathan signs off on the binding table before any code starts.** If a Figma variable has no PUI equivalent, STOP and ask whether to extend PUI or use the raw value.
2. **Snapshot → live-binding refactor across PropertiesListPane / EditPropertyPane / PropertyVisibilityPane.** Collapses 4-scope switches into "extract typeID + look up live from manager." Single change fixes delete-leaves-stale-row + add-doesn't-show + rename + duplicate, all at once. Read `PropertiesListPane.swift:70-82` (`resolvedProperties()`), `PropertyVisibilityPane.swift:112-125` (`parentTypeProperties()`), `EditPropertyPane.swift:~304` (`currentDefinition()`).
3. **Fix `definition.id == ""` route bug.** Edit `PropertyTypePickerPane.swift:69-84` to mint the property ID via `ReservedPropertyID.mintUserPropertyID()` BEFORE calling `addProperty`, then use the same ID in the route. (Manager mints inside `addProperty` but Swift's value semantics discard the mint at the caller.)
4. **Convert PropertyTypePicker from gallery to list.** Replace `LazyVGrid` at `PropertyTypePicker.swift:94` with vertical layout. Per-row: icon + name, no description.
5. **Redesign Select/Multi/Status option rows.** `PropertyChip(label, color) + chevron Button` per row, no drag handles. Chevron appends `.editOption(propertyID, optionValue)` to the popover navigation path. Pass `$path: Binding<[ViewSettingsRoute]>` down into both editors.
6. **Add `.onMove` to option editors + PropertyVisibilityPane.** Direct row drag, no handle. For Status: also implement cross-group drag via `.draggable` + `.dropDestination` with cascade-confirmation dialog on group-change drops.
7. **Filter reserved properties from PropertyVisibilityPane.** Only user props + `_modified_at` appear.
8. **User-friendly errors in PropertyTypePickerPane.** Add a `displayMessage(for: any Error)` mapping. Clear `commitError` on every fresh type tap.
9. **Wire Relation creation through RelationPropertyWizard.** Remove the no-op guard at `PropertyTypePickerPane.swift:58-65`. Push wizard into the popover NavigationStack; on complete, auto-route to EditPropertyPane.
10. **Fix Vault delete/rename.** `PageTypeRow.swift` — capture `pageType.id` once, look up fresh `pageType` inside handlers from the manager (stale-capture diagnosis from prior Explore agent).
11. **Close criterion: cross-scope (PageType + PageCollection + ItemType + ItemCollection) + cross-surface (popover + VaultSettingsSheet + TypeSettingsSheet) visual smoke from Nathan.** Per-gesture verification per the interaction matrix in the plan.

**Execution discipline for Slices 1, 2, and 3 (ALL three slices):**

- **STOP-and-ASK** when uncertain. No guessing about interaction, UX flow, design specifics, gesture behavior, error-state copy, drop-target affordances, or animation behavior. No "I'll pick something reasonable."
- **ZERO subagents for any frontend-touching work.** All SwiftUI / view-layer code is written in-line by Claude only. This applies to Slices 1, 2, AND 3 — every step that touches the View Settings popover, EditPropertyPane, EditOptionPane, options editors, PropertyVisibilityPane, PropertyTypePicker, detail-view Table columns, cell editor popovers, or any other UI surface. Subagents are permitted ONLY for: (a) read-only exploration of existing code, (b) `building-apple-platform-products` background xcodebuild verification per quirk #14.
- **Auto Mode OFF.** Explicit checkpoints with Nathan per major step.
- **Builder-subagent runs in background** per quirk #14 (`xcodebuild test -only-testing:PommoraTests`) — the only carve-out from the no-subagents rule, because it's verification not code-writing.

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
16. **(NEW this session)** **Popover-side surfaces read live from the manager via stable IDs.** `PropertiesListPane`, `EditPropertyPane`, `PropertyVisibilityPane`, `EditOptionPane` must NEVER read state from captured `ViewSettingsScope` payloads — always look up via type ID / property ID / option value from the live manager. View-state propagation equivalent of quirk #16 (env re-injection).
17. **(NEW this session)** **No drag handles in reorderable lists.** Direct row drag via user input. No `line.3.horizontal` icons, no visual drag-grip affordance. Row visual is clean; drag is invisible until user starts dragging.
18. **(NEW this session)** **Type pickers render as vertical lists, not galleries.** Icon + name per row, no description blurbs. Applies to PropertyTypePicker and any future type-selection surface.
19. **(NEW this session)** **Visibility lists show ONLY user properties + `_modified_at`.** Reserved IDs are filtered out — they have no place in a user-facing visibility list.

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

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **`main` at `0a0411a`, +37 commits ahead of `origin/main`, all local — `git push origin main` is still the auth-gated pending op.** This session approved a second plan: Properties UX rebuild at `.claude/Planning/2026-05-26-v0.3.1-properties-rebuild-plan.md`, replacing the existing-but-rough v0.3.1 popover-side Edit Properties surface. The Folders + CRUD plan stays approved but moves to queued. **PRIORITY: Properties rebuild Slice 1 — `v0.3.1.0.2 'Edit Properties actually works'`.** **HARD RULES for Slices 1, 2, AND 3:** (a) **STOP-and-ASK on any uncertainty** about interaction, UX flow, design, gesture behavior — no guessing. (b) **ZERO subagents for any frontend-touching work**; only read-only Explore for code-survey + background `building-apple-platform-products` for xcodebuild verification are permitted. (c) **Auto Mode OFF** — explicit checkpoints per major step. **FIRST MOVES for Slice 1:** (1) Nathan selects in Figma desktop app: EditPropertyPane root, EditOptionPane root, chip+chevron option-row variant, type-picker list row, PropertyVisibilityPane row. (2) Claude calls `mcp__claude_ai_Figma__get_design_context` + `mcp__claude_ai_Figma__get_variable_defs` per node. (3) Produce Figma → PUI binding table; Nathan signs off. (4) THEN code: snapshot→live-binding refactor (PropertiesListPane/EditPropertyPane/PropertyVisibilityPane — fixes delete + add + rename + duplicate in PageType/ItemType scopes); fix `definition.id == ''` route bug at `PropertyTypePickerPane.swift:84`; convert PropertyTypePicker from `LazyVGrid` gallery to vertical list (icon + name only); redesign Select/Multi/Status option rows (chip + chevron, NO drag handle); wire chevron to push `.editOption`; add `.onMove` to options + PropertyVisibilityPane (Status cross-group drag via `.draggable`/`.dropDestination` + cascade-confirmation); filter reserved properties from PropertyVisibilityPane; user-friendly errors in PropertyTypePickerPane; wire Relation creation through RelationPropertyWizard; fix Vault delete/rename in PageTypeRow. **Close criterion:** cross-scope (PageType + PageCollection + ItemType + ItemCollection) + cross-surface (popover + VaultSettingsSheet + TypeSettingsSheet) visual smoke from Nathan. Plan + this Handoff carry every locked decision — do not re-litigate. The Folders + CRUD plan resumes after all three Properties slices ship green."
