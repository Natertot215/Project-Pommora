### Pommora — History

Locked decisions, ordered by area. Brief by design — implementation detail lives in `PommoraPRD.md` and the feature docs.

#### Folders (third Pages-side tier) — tried and reverted (2026-05-27)

Built a full `PageType → PageCollection → Folder → Page` third tier (model, `_folder.json` sidecar, SQLite table, CRUD, sidebar + detail UI) then reverted it the same cycle. The tier duplicated Collections' rigid-grouping role while conflicting with the planned view-organization system (Board / group-by / saved views, v0.6.0): you can't "group by property" and display a fixed container hierarchy in the same view, and that primitive doesn't exist yet to prove folders were even needed. Removed before more features piled onto the third tier. **Kept** from the effort: F.0's system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`, `68caf96`), the sidebar context-menu tweaks (no "New Vault" in the row menu — "+" header is the sole vault-creation path; plain "New X" labels), and `NexusAdopter.autoTagMissingSidecars` for Types + Collections (drag a folder structure into a Nexus via Finder and it's recognized). Full removal plan: `.claude/Planning/2026-05-27-folders-removal-plan.md`.

#### v0.3.1 Properties end-to-end (2026-05-26 — shipped on main as 21 commits, baseline `627e972` → tip `0d5aa16`)

Single-session execution of the approved `.claude/Planning/View-Settings-edit-properties-plan.md` (25 tasks, 9 phases). Tasks 1-20 shipped + Task 21 (PropertyEditorRow stub patches in Item Window inspector) intentionally deferred to v0.3.1.x — the cell editor bypasses that dispatcher entirely so the headline UX ships without it. Task 23 (`git push` + Nexus mirror) paused for Nathan's auth.

**Phase ship map:**
- **Phase A — Data layer foundations** (Tasks 1-5b): `DisplayVariant` enum (`.box`/`.select`/`.chip`, Status-only render variant) + `DateFormat` enum (6 cases) + `PropertyDefinition.displayAs` + `.dateFormat` (additive Codable) + `ItemType.singular` (Capacities-style label) + `SavedView` Codable upgrade (real fields + reserved sort/filter/group stubs) + `views: [SavedView]` on PageCollection + ItemCollection + default-view migration on PageTypeManager.loadAll + ItemTypeManager.loadAll (quirk #15 pattern) + PropertyChipColor cleanup (12 cases — drop `.cyan`/`.mint`/`.gray`, add `.orange`/`.accent`; retire tier system; new OptionColorPicker 5x2 grid). 6 commits.
- **Phase B — ViewSettingsScope + popover scaffold** (Tasks 6+7): `ViewSettingsScope` gains associated values on the 4 storage cases (PageType/PageCollection/ItemType/ItemCollection) so popover content can render schema-aware bodies. NavigationStack popover scaffold + StorageMenuRoot (Notion-style menu with active Edit Properties + Property Visibility + muted Layout/Sort/Filter/Group rows). 2 commits.
- **Phase C — Schema editor extraction** (Task 8): SelectOptionsEditor + StatusGroupsEditor + NumberFormatPicker + FileAcceptEditor extracted from VaultSettingsSheet + TypeSettingsSheet into shared `Pommora/Properties/Editor/` module. Type-prefixed copies removed; both sheets reference shared definitions. 1 commit.
- **Phase D — Edit Properties pane** (Tasks 9-11b): PropertiesListPane (searchable + reserved-property lock badges + chevron-push) → PropertyTypePickerPane (type-aware routing: Select/Status/MultiSelect auto-push to EditPropertyPane after commit; simple types pop back; Relation defers to RelationPropertyWizard) → EditPropertyPane (Notion-format: header + Type row + per-type middle section + Duplicate + Delete footer; live-save via new `updateProperty(id:in:transform:)` per manager) → EditOptionPane (per-option editor pushed via `.editOption` route; chevron-push wiring from SelectOptionsEditor deferred to v0.3.1.x). 4 commits.
- **Phase E — Property Visibility pane** (Task 12): click-to-toggle + strikethrough-on-hidden + locked `_modified_at` (always visible per locked decision). Writes via new `updateView(viewID:in:transform:)` per manager (resolves containerID as PageType / PageCollection / ItemType / ItemCollection automatically). 1 commit.
- **Phase F — Single-property value writes** (Tasks 13+14): `updatePageProperty` + `updateItemProperty` atomic single-property writes on PageContentManager + ItemContentManager. Read-modify-write via existing atomic save infrastructure; modifiedAt bumped on every write; SQLite index upsert best-effort. Dual-relation reverse-mirror via DualRelationCoordinator deferred to v0.3.1.x. 1 commit.
- **Phase G — Dynamic Table columns** (Tasks 15-18): PropertyColumnBuilder descriptor + 3 new chip primitives (RelationChip / FileChip / LinkChip) + PropertyCellDisplay dispatcher rendering all 11 property types (chip-family for Status/Select/Multi/Relation; pure text for Number/Date/URL/LastEdit; native control for Checkbox; File via FileChip overflow counter). Wired into all 4 storage detail views via `TableColumnForEach` (macOS 14+ — the plan's "no dynamic columns" note was outdated). 4 commits.
- **Phase H — Click-to-edit cell popovers** (Tasks 19+20): PropertyCellEditor wraps PropertyCellDisplay with a `.popover(arrowEdge: .bottom)` anchor; per-type editor dispatch inside the popover (number/date/datetime/select/multiSelect/status/url use built-ins or existing pickers; checkbox flips inline without popover; lastEditedTime stays read-only; relation + file show "v0.3.1.x" placeholder until IndexQuery + AttachmentManager flow-through ships). Detail views compute commit closures that route to updatePageProperty/updateItemProperty with the right parent collection (helpers `collectionContaining(pageID:)` + `setContaining(itemID:)` scan cache for membership). 2 commits.

**Locked decisions ratified this session:**

- **PropertyChipColor flat palette (12 cases).** `.default` (nil/grey fallback) / `.red` / `.orange` / `.yellow` / `.green` / `.blue` / `.accent` (Nexus accent) / `.teal` / `.indigo` / `.purple` / `.pink` / `.brown`. `.cyan`/`.mint`/`.gray` retired. Green + Teal use `.opacity(0.7)` Apple system colors. Yellow + Pink keep Pommora custom hex. `selectablePalette` returns the 10 user-pickable cases (excludes `.default` + `.accent`) for OptionColorPicker's 5x2 grid.

- **DisplayVariant is Status-only.** `.box` / `.select` / `.chip`. Other property types ignore `displayAs`. The `.chip` variant uses hardcoded `"square.dashed"` placeholder icon at v0.3.1.x; per-group / per-option Status icons + Settings config land in pre-v1 cleanup (Prospects.md).

- **DateFormat is Date/DateTime-only.** 6 cases including ISO 8601. Default `.monthDayYearLong`. Custom strftime-token formats deferred (Prospects.md).

- **Chip rendering scope (cell display side).** Chips render ONLY for Status / Select / MultiSelect (via PropertyChip pill) + Relation (via RelationChip — RoundedRectangle cornerRadius 4) + File (via FileChip — quaternary fill, link icon). Dates / Links / Numbers / Checkboxes / LastEditedTime render as pure text or native controls without chip chrome.

- **Each Collection's `views[]` is independent of the parent Type's.** SavedView lives on both PageType + PageCollection (and ItemType + ItemCollection) separately. Default-view migration in `loadAll` mints a fresh Table view per container that has empty views.

- **Schema lives on the Type; Collections inherit.** Edit Properties pane shown for Collection scope writes to the parent Type's schema via `c.typeID` lookup. Property Visibility pane writes to the Collection's own views[0].

- **TableColumnForEach works on macOS 26.** Plan note about "no dynamic columns on macOS" was outdated. Detail views use TableColumnForEach for the user-property column band between Title and Modified.

- **`updateProperty(id:in:transform:)` on each Type manager.** Generic transform-based per-config edit. Replaces a hypothetical `updateOption(...)` method — EditOptionPane reuses the same `updateProperty(transform:)` flow with closure-based option lookup. Same pattern for `updateView(viewID:in:transform:)`.

**Sub-tasks intentionally deferred to v0.3.1.x:**
- Task 21 (PropertyEditorRow relation/status/file stub patches in Item Window inspector) — cell editor bypasses entirely; sheet path stays current behavior.
- Cell-editor inline Relation editor (needs IndexQuery flow-through to cell editors).
- Cell-editor inline File editor (needs AttachmentManager flow-through to cell editors).
- SelectOptionsEditor + StatusGroupsEditor chevron-push refactor (would light up EditOptionPane in normal UX; today EditOptionPane is route-addressable but unreachable through the editors).
- Dual-relation reverse-mirror inside updatePageProperty + updateItemProperty.
- Per-option Status icons + Settings config (pre-v1 cleanup).
- Tests for `updatePageProperty` + `updateItemProperty` value-write paths (defer to a test-coverage patch; cell-editor smoke testing relies on visual verification at this slice).

**Working tree merge note:** Nathan's parallel session on Vault/Collection adoption (file-explorer add path) will conflict with my Phase A Task 5 default-view migration in PageTypeManager.loadAll + ItemTypeManager.loadAll. Quirk #11 anticipated this; rebase / merge resolution happens when his work lands.

#### v0.3.x View Settings chrome slice (2026-05-25 evening — first patch of v0.3.1.x Storage View Redesign)

Same-day continuation of the PM sweep. One focused commit on `v0.3.0-properties`; merged to `main` and pushed alongside. Ships the chrome of the consolidated View Settings popover — empty Liquid Glass shell behind a `slider.horizontal.3` toolbar button — while locking the architectural pattern every follow-up panes patch will reuse.

**Ship list:**

| Component | File | Outcome |
|---|---|---|
| Scope enum | `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift` | 10-case enum (one per `SidebarSelection` variant; `.savedKey("calendar")` collapses to `.calendar`, other saved keys collapse to `.none`). Case-only at this slice; associated values added in v0.3.1 when first real pane needs entity refs |
| Empty popover shell | `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift` | `Color.clear.frame(width: 300, height: 360)`. Liquid Glass auto-inherits from toolbar anchor (WWDC25 #323). Outside-click + ESC are the only dismiss paths — no in-popover close affordance |
| Toolbar button | `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift` | `Button { } label: { Image("slider.horizontal.3") ... }` + `.popover(arrowEdge: .top)`. 22x16 icon frame matches Inspector toggle next to it for capsule uniformity |
| Test coverage | `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift` | 13 tests covering every `SidebarSelection` case + the 4 `.savedKey` variants (`"calendar"` / `"homepage"` / `"recents"` / unknown). All green |
| ContentView wiring | `Pommora/Pommora/ContentView.swift` | `static func viewSettingsScope(for:)` pure mapper + `private var currentViewSettingsScope` reactive computed property. Button inserted as FIRST child of the existing primary-action HStack — shares the existing `.glassEffect()` capsule with NavDropdown + Inspector toggle. Order: `[ViewSettings] [NavDropdown] [InspectorToggle]` |

**Architecture locked (locked decision #12):** static button position at ContentView level + adaptive popover content via `ViewSettingsScope` derived reactively from `sidebarSelection`. Detail views never declare their own `.toolbar { ... }` for this surface. SwiftUI re-evaluates the scope parameter when selection changes; the popover body (when open) re-renders against the new scope; the button itself never moves. Forward-compat: in v0.3.1 the enum gains associated values carrying concrete entities; the wiring shape doesn't change, only the body content.

**Bug found + fixed mid-session via systematic-debugging:** initial popover header used `Button(role: .close) { dismiss() }` — the role-only init that infers an X label from the role. Apple only documents this inside `.toolbar { ... }` context where SwiftUI synthesizes the X. Inside a popover body (non-toolbar context) it asserted at first popover-content render — crash on button click (popover content is lazy-evaluated, so render fires on tap, not at app launch). Root-cause located via Phase 2 pattern analysis: my usage was the only `Button(role: .close)` in the entire codebase; every other `Button(role:)` paired the role with explicit `label:` content. Surgical fix: replaced with `Button { dismiss() } label: { Image("xmark.circle.fill") ... }.buttonStyle(.plain)`. Then user requested empty placeholder per the chrome-only slice scope; close button removed entirely. Locked as new quirk #17.

**Locked decisions this slice:**

1. **View Settings button = single static instance at ContentView level inside the existing primary-action `.glassEffect()` HStack.** Order: `[ViewSettings] [NavDropdown] [InspectorToggle]`. NEVER per-detail-view. Popover content adapts via `scope: ViewSettingsScope` parameter derived from `sidebarSelection`. Recorded as locked decision #12 in Handoff.

**Plan record:** `.claude/Planning/View-Settings-button-chrome-plan.md`. Tasks 1-4 (button + popover + scope wiring + ContentView insertion) shipped this commit; Task 5 (visual approval on all 9 surfaces) is the remaining open item. Plan stays in active Planning until Task 5 closes; then retires to Superseded.

---

#### v0.3.x follow-up sweep (2026-05-25 PM — 17 commits on `v0.3.0-properties`)

Same-day post-merge: design-system foundations + UX correctness sweep + one architectural fix. Branch tip `88c9367` on `origin/v0.3.0-properties`.

**Ship list (chronological):**

| Cluster | Tip commit | Outcome |
|---|---|---|
| Items-Detail-Views plan Tasks 1-11 | `55bf8c3` | All 4 storage detail views (PageType / PageCollection / ItemType / ItemCollection) shipped with footer (`+ New …` buttons) + session-local drag-reorder via `DetailRowDragPayload` + `SessionRowOrdering`. Real `NewItemSheet` replaces stub. PageCollectionDetailView strips duplicate sort UI. Kind column removed from Items-side views (homogeneous content) |
| Sidebar disclosure restore | `dd441f1` | Reverses earlier flatten-to-leaf. Item Types fold like Vaults; Sets render as flat leaves WITHOUT chevrons. `ItemTypeManager.parentItemType(for:)` helper. New `SidebarConfirmation.deleteItemCollection` case. Mitigates structural-asymmetry crash risk per quirk #9 (mixed flat-leaf + disclosure children in same Section crashed `OutlineListCoordinator.recursivelyDiffRows`) |
| Items section label | `675e378` | Sidebar default `"Types"` → `"Items"` (`SettingsLabels.SidebarSectionLabels.defaults`). `Settings.currentDefaultsVersion` 1→2 with migration step that only rewrites users still on the old default. `"Delete Type"` → `"Delete \(typeLabel)"` via newly-injected `@Environment(SettingsManager.self)` on top-level SidebarView |
| Real stub-replacement sheets | `9a6aac0` | `NewItemTypeSheet` + `NewItemCollectionSheet` get real Name + Icon forms (was 23-24 line "UI ships in follow-up" stubs). Mirror `NewPageTypeSheet` / `NewPageCollectionSheet` shape |
| Chip primitives + PommoraUIX | `cedb75b` | NEW `Pommora/Properties/Chips/` folder: `PropertyChip` (pill + chip variants, 13-color `PropertyChipColor` palette in 2 tiers — `.pink = #E89EB8` / `.yellow = #FFDE21` are Pommora-custom hex overrides), `PropertyCheckbox` (custom icon + color), `ChipDropdown` (Liquid Glass, content-driven width). NEW `Pommora/ComponentLibrary/` folder: `ComponentLibraryView` Cmd+Shift+D debug window with gallery-style flat per-category leaves (Chips / Sidebar / Detail Views / Sheets / Page Editor / NavDropdown / Windows + Foundations). `PropertiesPulldown` removed from `PageEditorView` (obstructed titlebar; properties for Pages will live in Claude chat inspector slot v0.3.x). NEW spec at `.claude/Features/PommoraUIX.md` |
| Env-injection crash fix | `c8b3cbc` | `ItemTypeDetailView` + `ItemCollectionDetailView` declare `@Environment(ItemTypeManager.self)` + `@Environment(SettingsManager.self)` but `ContentView.detail` only injected `spaceMgr / vaultMgr / contentMgr / itemContentMgr`. SwiftUI `_TaskValueModifier.Child.value.getter` asserted in `EnvironmentValues.subscript.getter` (`EXC_BREAKPOINT` SIGTRAP) when computing the `.task` closure for the detail view. Added the missing two env values to the optional-unwrap chain + `.environment(...)` chain |
| Icon pipeline | `09e7a27` | `ItemContentManager.createItem(name:in:type:)` + `createItem(name:inTypeRoot:)` gain `icon: String? = nil`. Same for `PageContentManager.createPage(name:in:vault:)` + `createPage(name:inVaultRoot:)`. Both managers persist the icon into entity's icon field (was hardcoded `nil`, silently discarding the IconPickerField selection). `NewItemSheet` passes through. `NewPageSheet` gains `IconPickerField` (was missing entirely) + frame expanded 380x220 → 400x260 |
| Label sweep | `a8bd20b` | `TableColumn("Name")` → `TableColumn("Title")` in all 4 detail views. `TextField("Name", text:)` → `TextField("Title", text:)` in 8 sheet form files + 4 detail-view rename alerts. `"Tier 1 (Spaces)" / "Tier 2 (Topics)" / "Tier 3 (Sub-topics)"` → `"Spaces" / "Topics" / "Projects"` in `ItemWindow.relationsSection` + `RelationPropertyWizard` tier picker (drops `"Tier #"` prefix per locked 2026-05-25 directive) |
| **SQLite FK fix** | `88c9367` | `PageTypeManager.loadAll` + `ItemTypeManager.loadAll` defensively upsert types + collections to the SQLite index after disk-load. Eliminates recurring `SQLite error 19: FOREIGN KEY constraint failed - INSERT OR REPLACE INTO pages...` toast that fired when CRUD ran against entities loaded from disk that the index DB had no record of (adoption / external Finder folders / post-adoption state). Establishes new invariant locked as quirk #15: "after loadAll, every in-memory parent is mirrored to DB." `INSERT OR REPLACE` keeps it idempotent; `try?` swallows failures since index is regeneratable. 4 regression tests in new `LoadAllIndexSyncTests.swift` lock the invariant against future regressions |

**Locked decisions this sweep:**

1. **Items + Pages are NOT renameable concepts.** Only their containers (Vault / Collection / Type / Set) get `LabelPair` entries in `SettingsLabels`. `"New Item"` and `"New Page"` literals are correct; no `settings.labels.item` / `.page` exists.
2. **Sidebar Items section default = `"Items"`** (not the container plural `"Types"`). Users browsing this section think of it as "browsing my Items," not "browsing my Types." Renameable per Nexus.
3. **Item Types are sidebar disclosure-toggles** mirroring Vaults; their Sets render as flat leaves WITHOUT chevrons (no further sidebar children to disclose). Items themselves never appear as sidebar rows — they live in the detail-pane Table.
4. **Tables: NO vertical column borders.** Notion-flat aesthetic. Only horizontal bottom-of-header underline. Forward-applies to all 4 storage detail views + v0.5.0 view-type renderers. SwiftUI Table needs NSViewRepresentable + cleared `gridStyleMask` to enforce — implementation TBD with the v0.3.1.x Storage View Redesign spec.
5. **Tier labels in property panels = `"Spaces" / "Topics" / "Projects"`** (no `"Tier #"` prefix). Matches the 2026-05-25 sidebar-section directive. Hardcoded for v0.3.x; will thread `SettingsManager` when v0.6.0 Settings UI ships.
6. **`"Title"` everywhere, not `"Name"`.** Column headers, form placeholders, rename dialogs. Aligns with the `title` field name on every entity.
7. **`loadAll` syncs parents to index** (quirk #15). Forward-binding architectural invariant.
8. **Every detail-view `@Environment` must be injected at `ContentView.detail`** (quirk #16). Forward-binding architectural invariant.

**Active brainstorm — v0.3.1.x Storage View Redesign:** Research done (Notion UX patterns + SwiftUI primitives), captured at `.claude/Planning/View-Settings-research-notes.md`. Spec NOT yet written. Plans to write spec next session. Locked decisions: toolbar `slider.horizontal.3` popover with `NavigationStack` submenus mirroring Notion's view-settings menu structure; per-view config storage in `views[]` array per sidecar (one entry today, multi at v0.5.0); Property Visibility row = strikethrough toggle (no eye icon); delivery via Approach B patch-series drip v0.3.1 → v0.3.1.4.

---

#### v0.3.0 Properties — FEATURE-COMPLETE; merged to main (2026-05-25)

71 commits on `v0.3.0-properties` merged into `main` as `3d1bc19`. All 11 phases A–K shipped end-to-end. Smoke test on Nathan's real nexus is the only remaining gate before release tagging.

**Full phase ship list:**

| Phase | Scope | Tip commit |
|---|---|---|
| A.1–A.6 | Foundation types (11-case `PropertyType`; `PropertyValue` + `FileRef`; `ReservedPropertyID` + `mintUserPropertyID`; 5-case `RelationScope` tagged-object; `PropertyDefinition` stored ULID `id` + config fields + nested `StatusGroup`/`StatusOption`/`StatusGroupID` + `DualPropertyConfig`) | `1f85548` |
| B.1 | `SchemaTransaction` atomic multi-file commit primitive | `f31bda0` |
| C.1, C.3, C.4, C.5 | Migration suite: `PageFrontmatter.modifiedAt` + `schema_version: 1` on every sidecar + `PropertyIDMigration` two-phase scan/apply runs every nexus open + `AdoptionPreviewView` surfaces per-Type migration counts before commit | `87dcf76` (+ fix `c60fe48`) |
| D.1–D.8 | Schema CRUD on all 4 schema-bearing managers (`addProperty`/`renameProperty`/`changeType`/`deleteProperty`/`reorderProperty`); `PropertyDefinitionValidator` 8 rules; `schemaByID` rewire + drop `duplicateTitle`; `default_sort` on every sidecar; `SchemaConflictDialog` EC4 drift defense | `516e2e5` |
| E.1–E.7.5 | SQLite index live end-to-end: GRDB.swift SPM dep; `PommoraIndex.open(at:)` lifecycle with schema-version recovery; 12-table schema; `IndexBuilder` two-phase populate; `IndexUpdater` wired into all 6 managers; `IndexQuery` Notion-style filter+sort+broken-links; `NexusManager` opens/rebuilds; `ContentView.constructManagers` plumbs `IndexUpdater` so mid-session mutations propagate | `0b629bc` (+ name-match fixup `ef43eb9`) |
| F.1–F.2 | `AttachmentManager` copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/` with MIME accept-list (wildcard support), 50 MB warn / 500 MB hard cap, collision-safe filename suffixing; cascade-delete to trash on entity delete across all 4 entity managers | `7bb883d` |
| G.1–G.5 | AgendaTask + AgendaEvent schema defaults inject `_status` Status property; load-path backfill for pre-existing schemas via SchemaTransaction; `DualRelationCoordinator` manages paired-relation lifecycle (create/value-mirror/rename/delete); wired into `PageTypeManager` + `ItemTypeManager.addProperty`/`deleteProperty` to route paired relations through coordinator | `13af10f` (+ validator fix `71ce2da`) |
| H.1–H.2 | `movePageAcrossTypes` / `movePageBetweenCollections` on `PageContentManager+CRUD`; parallel `moveItem*` on `ItemContentManager+CRUD`. Name-based strip (property IDs are globally unique so ID-match is structurally impossible). Paired-relation back-ref cascade-clear. SchemaTransaction atomic across move + strip + back-refs | `7058991` |
| I.1+I.2 | `Settings.defaultsVersion` field + `Settings.migrate(_:)` step-function scaffold; `SettingsManager.loadOrSeed` calls `migrate` after decode + re-persists only when changed (mtime stays stable on no-op launches); 4 auto-migration tests | `b6c970a` |
| J.1–J.15 | Placeholder UI suite: PropertyEditorRow dispatches all 11 types; `ItemCollection.pinned_properties`; `StatusPicker` 3-section popover; `RelationPicker` scope-aware (GRDB `String` overload pollution workaround via private struct sub-views); `FileAttachmentEditor` with size-warning flow; `RelationPropertyWizard` 5-step (`DualRelationCoordinating` protocol for mockable tests); `PropertyTypePicker` 10-case (excludes `.lastEditedTime`); `VaultSettingsSheet` + `TypeSettingsSheet` schema editors; `MoveStripConfirmationDialog`; `PropertyPanel` host-agnostic eager panel; Item Window inspector toggle + pinned chips; `PropertiesPulldown` lazy mounted in `PageEditorView`; `FrontmatterInspector` live editors; column-header click-to-sort on `PageCollectionDetailView` | `f14c881` (J.15) |
| I.3 | `SidebarSectionLabels.spaces` + `.topics` fields; sidebar section headers + sheet titles thread from `SettingsManager.labels` instead of hardcoded literals | `345a9df` |
| K.1+K.2 | `CalendarDetailView` (Tasks list above, Events list below; sorted by due/start ascending; nil-date last); right-click Calendar pin → "New Task" / "New Event" quick-create | `fc7e0f8` + `11a7f45` |

**Parallel-session merge during branch:** `c98ecd6` (drag-reorder native `.onMove` rebuild + `RenameableRow` extraction during Phase C.5) + `2fada62` (sidebar native-selection migration: new `NSTableSelectionStyleSuppressor`, expanded `SidebarSelection` model, sidebar row + view polish across 14 files).

**Locked decisions this branch:**

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.** Matches `{"$rel": id}` relation pattern. Pure shape-sniff at the Codable layer can't disambiguate `.status` from `.select`; tagged form is round-trip-stable AND agent-legible.
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`; ID-based cross-type matching is structurally impossible. `IndexQuery.moveStripCount` filters by name; Pages keep values where dest has a same-named property.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1`, `_tier2`, `_tier3`, `_wikilinks`. User-defined properties mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.** Legacy decode → 0 = needs migration. Index DB carries its own `schema_version` in `meta` table; mismatch triggers delete + rebuild.
5. **`PropertyIDMigration` runs on EVERY nexus open** (not only when adoption is also needed). Idempotent. Preview sheet shows per-Type counts before commit.
6. **tier1/2/3 are root-level frontmatter fields**, not nested under `properties:`. Reserved IDs `_tier1`/`_tier2`/`_tier3` block user collisions. Edited via `ContextTierPicker`.
7. **AgendaTask + AgendaEvent default seed = single `_status` Status property.** Legacy `type` Select removed. Load-path migration injects on existing schemas via `SchemaTransaction`.
8. **`DualRelationCoordinator` is the lifecycle owner of paired relations.** Manager `addProperty`/`deleteProperty` route paired-relation work through it; container-scoped relations get atomic dual creation, value mirroring on set/clear, atomic delete-with-value-cascade.
9. **`AttachmentManager` is the only path for file values.** Copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/`; 50 MB warn / 500 MB hard cap; cascade-delete to trash on entity delete.
10. **Settings carries `defaultsVersion: Int`** for forward-compatible stale-default migration. `Settings.migrate(_:)` is the step-function scaffold; bump the constant + add a migration step when defaults change.

**Next session opens at:** v0.3.1 — Properties Pulldown + Property Panel polish (Figma-driven fast-follow). Plus smoke test of v0.3.0 on Nathan's real nexus before tagging.

---

#### v0.3.0 Properties — Phases A–G shipped on `v0.3.0-properties` (2026-05-24 EOD)

44 commits on branch (off `main`). Build green; full unit suite passing with two known pre-existing failures (`NexusAdopterTests/applyNathansActualShape` from parallel-session NexusAdopter working-tree change + `PageEditorViewModelTests/debounceCoalescesRapidEdits` flake under full-suite load).

**Phases shipped (in commit order):**

| Phase | Scope | Commit |
|---|---|---|
| A.1–A.6 | Foundation types: 11-case `PropertyType`; `PropertyValue` + `FileRef`; `ReservedPropertyID` + `mintUserPropertyID`; 5-case `RelationScope` (tagged-object on-disk); `PropertyDefinition` stored `id` + config fields + `StatusGroup`/`StatusOption`/`StatusGroupID` + `DualPropertyConfig` nested | `cd61ed4`–`1f85548` |
| B.1 | `SchemaTransaction` atomic multi-file commit primitive | `f31bda0` |
| C.1, C.3, C.4, C.5 | Migration suite: `PageFrontmatter.modifiedAt` + `schema_version: 1` on every sidecar + `PropertyIDMigration` two-phase scan/apply API runs every nexus open + `AdoptionPreviewView` surfaces migration counts before commit | `d69fd97`, `3afeec9`, `8ff9dc9`, `87dcf76` (+ fix `c60fe48`) |
| D.1–D.8 | Schema CRUD on all 4 schema-bearing managers (`addProperty`/`renameProperty`/`changeType`/`deleteProperty`/`reorderProperty`); `PropertyDefinitionValidator` 8 rules; `schemaByID` rewire + drop `duplicateTitle`; `default_sort` on every sidecar; `SchemaConflictDialog` EC4 drift defense | `5e6a0de`–`516e2e5` |
| E.1–E.7.5 | SQLite index live end-to-end: GRDB.swift SPM dep; `PommoraIndex.open(at:)` lifecycle with schema-version recovery; 12-table schema; `IndexBuilder` two-phase populate (MainActor walk → `Sendable` snapshot → single GRDB transaction); `IndexUpdater` wired into all 6 managers; `IndexQuery` Notion-style filter+sort+broken-links; `NexusManager` opens/rebuilds index; `ContentView.constructManagers` plumbs `IndexUpdater` so mid-session mutations propagate | `064f8dc`–`0b629bc` (+ name-match fixup `ef43eb9`) |
| F.1–F.2 | `AttachmentManager` copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/` with MIME accept-list (wildcard support), 50 MB warn / 500 MB hard cap, collision-safe filename suffixing; cascade-delete to trash on entity delete across all 4 entity managers | `d696100`, `7bb883d` |
| G.1–G.5 | AgendaTask + AgendaEvent schema defaults inject `_status` Status property; load-path backfill for pre-existing schemas via SchemaTransaction; `DualRelationCoordinator` manages paired-relation lifecycle (create/value-mirror/rename/delete); wired into `PageTypeManager` + `ItemTypeManager.addProperty`/`deleteProperty` to route paired relations through coordinator | `9edb2db`–`13af10f` (+ validator regression fix `71ce2da`) |

**Locked decisions this branch:**

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.** Matches the `{"$rel": id}` relation pattern. Pure shape-sniff at the Codable layer can't disambiguate `.status` from `.select` (both single strings); tagged form is round-trip-stable AND agent-legible.
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`, so ID-based cross-type matching was structurally impossible. `IndexQuery.moveStripCount` filters by name; a Page keeps property values where the destination has a property of the same name.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1`, `_tier2`, `_tier3`, `_wikilinks`. User-defined properties mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.** Legacy decode → 0 = needs migration. Index DB carries its own `schema_version` in `meta` table; mismatch triggers delete + rebuild.
5. **Property-ID migration runs on EVERY nexus open** (not only when adoption is also needed). Idempotent. Preview sheet shows per-Type counts before commit.
6. **Tier1/2/3 are root-level frontmatter fields**, not nested under `properties:`. Reserved IDs `_tier1`/`_tier2`/`_tier3` block user collisions.
7. **`AgendaTaskSchema` + `AgendaEventSchema` default seed = single `_status` Status property.** Legacy `type` Select removed. Load-path migration injects on existing schemas via `SchemaTransaction`.
8. **`DualRelationCoordinator` is the lifecycle owner of paired relations.** Manager `addProperty`/`deleteProperty` route paired-relation work through it; container-scoped relations get atomic dual creation, value mirroring on set/clear, atomic delete-with-value-cascade.

**Parallel-session state:** sidebar drag-reorder native `.onMove` rebuild + `RenameableRow` extraction merged into branch as `c98ecd6` during C.5. End-of-day working tree carries ~15 uncommitted sidebar/manager mods + 1 untracked `Sidebar/NSTableSelectionStyleSuppressor.swift` + 1 untracked plan doc from a continuing parallel sidebar-color iteration — quirk #11 (hands-off).

**Next session opens at:** Phase H (move-strip primitive + cross-Type move methods on `PageContentManager` + `ItemContentManager` using `SchemaTransaction`). Then I (settings scaffold + auto-migration), J (placeholder UI suite, ~15 sub-tasks), K (Calendar pinned list view). After J + K land, v0.3.0 is shippable end-to-end.

---

#### v0.3.0 Properties scope redirection + editor patches (2026-05-23 EOD)

Three shipped threads + a Properties scope brainstorm. Build green, **365/365 tests passing** (one timing flake in `PageEditorViewModelTests/debounceCoalescesRapidEdits` re-runs clean; unrelated to scope).

**Editor patches (parallel session):**

1. **Foldable headings toggle — fixed.** Heading chevron-on-hover + collapse mechanism now works correctly; frontmatter persistence via `folded_headings` round-trips. Resolves the long-running toggle bug in `External/MarkdownEngine/`.
2. **Em-dash / en-dash auto-syntax.** Trivial editor add: `--` → en-dash (`–`), `---` → em-dash (`—`). Ships with the heading-fold work.

**Properties scope redirection (brainstorm session — supersedes prior implementation plan):**

3. **v0.3.0 scope narrowed: data layer + minimum-viable placeholder UI only.** Real Properties Pulldown + Property Panel UI redirected to v0.3.1 (Figma-driven fast-follow). Broader inspector architecture (Claude chat as main-window inspector, PreviewWindow primitive, Item Window redesign with pinned chips) ships as separate v0.3.x patches with TBD timing. Effort estimate dropped from ~7.5 sessions to ~5.5 sessions. Items dropped from v0.3.0: `panel_hidden_properties` data field, `_itemcollection.json` `pinned_properties` field, seven-section Type Settings sheet (collapses to Edit Properties + Sort only), SchemaEditorRouter, concurrent-open guard, MultiSelectChips color refactor, all detail-pane property-column work, all right-click cross-surface routing.

4. **Surface architecture locked.** Properties live in three context-specific surfaces:
   - **Pages in main window** → NavDropdown-style pulldown at top of content (v0.3.1)
   - **Page Preview** → property panel in window's own inspector (toggle, default closed); ships with PreviewWindow primitive
   - **Item Window** → property panel in popover's own inspector + pinned-property chips above title (saved at Item Collection level); ships with Item Window redesign
   - **Main window inspector** → Claude chat (CLI subprocess bridge; ships independently); properties NEVER live here

5. **Six conceptual decisions locked** (added as decisions #21-#26 in spec):
   - Lazy properties: "+ Add property" picker only lists EXISTING schema properties not yet populated on this entity. Brand-new schema entries go through Type Settings.
   - Per-Type property order: drag-reorder in any surface writes to the parent Type's per-kind sidecar declaration order (affects every entity of that Type). No per-entity override at v0.3.0.
   - Empty surface state: "No properties" message + "+ Add property" affordance. Surface stays visible.
   - Pinning: right-click property row → "Pin Property" / right-click chip → "Unpin Property". Per-Item-Collection scope (shared across all Items in Collection).
   - Status universal: addable to PageType / ItemType / AgendaEvent manually. EventKit relevance is silent on non-Agenda Types — agent-readable as informational data shape.
   - Live red-border validation: invalid values render red as user types; failed saves silently revert.

6. **AgendaTaskSchema `defaultSeed()` rewritten in plan** — drops the placeholder `type` Select (`[Task, To-Do, Phase]`); Status becomes the sole built-in (per spec § Status property type). A.7.5 plan task documents load-path migration for existing nexuses (idempotent removal of legacy `type` if `builtin: true`; injection of Status if missing).

7. **`SchemaTransaction` shape extended to compound mode** (`schemaWrites: [SchemaWrite]`) — dual-relation create/delete rides one transaction; no `try? src.rollback()` orchestration needed. Resolved the rollback API inconsistency from the earlier audit.

8. **Properties.md + spec + plan + PRD + Framework + Pages.md + Items.md + PageTypes.md + Prospects.md doc sweep.** Properties.md gains canonical "Where Properties Live" section. Pages.md gains "Properties Pulldown — to-be-implemented" section. Items.md gains "Inspector Panel + Pinned Chips — to-be-implemented" section. Prospects.md retires "Property panel placement options" + promotes "Claude chat in inspector" out of Prospects (now in roadmap). PRD's three-pane shell description rewritten to reflect Claude-as-inspector direction. AgendaTask + AgendaEvent kind descriptions in PRD lose stale `type` Select reference.

**Sidebar bugfixes + UX tightening:**

9. **Sidebar disclosure-click bug — fixed (introduced drag regression).** Vault / Topic / PageCollection rows weren't expanding to show their children. Root cause: `.draggable` (inside `.reorderable(...)`) was applied to the entire DisclosureGroup, swallowing chevron clicks as drag-init gestures. Fix: moved `.reorderable(...)` from outer modifier into the DisclosureGroup's `label:` closure on PageTypeRow / PageCollectionRow / TopicRow — drag source stays the label area only, chevron tap area free for expand/collapse. **Side effect:** drag-to-reorder hit zones shrunk to label area only, and `rowHeight` measurement broke (label height ≠ full row height → above/below drop position calc is off). Drag feels non-functional. **Queued for follow-up:** split drag source from drop destination — `.draggable` on label only, `.dropDestination` on full row. See Handoff "Sidebar drag-to-reorder REGRESSION."

10. **Sidebar header label "Pages" → "Vaults"** — Nathan's `.nexus/settings.json` carried stale `sidebar_sections.pages = "Pages"` from before `SidebarSectionLabels.defaults()` was updated to `"Vaults"` / `"Types"` (`da744ab` 2026-05-23 morning). Direct file edit on Nathan's nexus. SidebarView code comment updated to reflect new defaults. **Settings migration shim queued** as Open Question #9 in Handoff (for future users with same stale state).

11. **PageType context menu cleanup** — verbose action labels stripped: "New Vault" / "New Collection" / "New Page". Direct-page-to-vault path was already wired via `NewPageSheet(parent: .vaultRoot(v))`; just relabeled cleanly.

#### Post-flatlayout hardening cluster (2026-05-23)

Five follow-up commits on `main` after the `flatlayout` tag (`049df19`), addressing issues Nathan found running the app post-ship on his real nexus. Each shipped green standalone; build green at cluster close, **366 tests passing** (+3 from the ship tag's 363).

1. **`2d42d63` fix(adopter): adoption preview fires only on structural migration.** `AdoptionPlan.hasAnythingToAdopt` no longer triggers on `freshSidecars` — only `inPlaceRenames` (legacy v0.2 migration), `unwrapSteps` (paradigmV2 wrapper unwrap), and `warnings` (explicit issues). Non-Pommora folders at root (Obsidian organization, etc.) stay invisible to discovery instead of spamming the adoption preview every launch. Per-folder opt-in adoption UI is a future Prospect. New test: `adoptionNoOpOnUnPommoraFoldersAtRoot`.

2. **`9cd8cd1` feat(sidebar): drag-to-reorder Phase 2 UX (v0.2.8).** Wired `.reorderable(...)` modifier (built in Phase 1 but never used in production) onto PageType / Topic / Space / Page / PageCollection / Project rows. Removed residual no-op `.onMove { ... }` modifiers (iOS/iPad pattern; doesn't fire on macOS without EditMode). Phase 1 persistence (`5a264f0`) was already correct — only the UX was missing. Out of scope: Items-side rows (ParadigmV2 stubs), NavDropdown Pinned reorder, cross-container drag, detail-pane Table reorder (Phase 4).

3. **`9c3820c` fix(detail): folder-name fallback + diagnostic info for "Collection parent vault not found".** `SidebarDetailView.lookupVault` gains a folder-name-match fallback when typeID-match fails — rescues users whose stored typeID drifted from the live PageType id (data-state caused by re-init / migration anomalies). Error UI surfaces diagnostics (collection title + typeID + parent folder name + full list of known vault IDs) so users can paste into bug reports if the fallback also fails.

4. **`5234f78` fix(adopter): cleanup co-located per-kind sidecar orphans; suppress noisy warning.** `cleanupLegacyOrphans` extended via new `cleanupOrphansAt` helper. Deletes orphan sidecars co-located with the authoritative per-kind sidecar — both other per-kind sidecars (e.g. `_pagecollection.json` next to `_pagetype.json` at vault-root) AND legacy `_vault.json` / `_collection.json` / `_schema.json`. Multi-sidecar warning suppressed at scan time (fires routinely for nexuses migrated through early flatlayout-4.2 versions; cleanup at apply handles silently). **Rule encoded:** at any folder level, only ONE per-kind sidecar is authoritative. The authoritative one wins via `recognizedSidecarsAt`'s order (pageType > itemType > taskConfig > eventConfig > pageCollection > itemCollection) — matches the natural-parent-inference rule (a root folder with both `_pagetype.json` + `_pagecollection.json` is a Type, not a Collection, because Collections must nest inside a Type). Triggered by Nathan's nexus having `Materials/_pagecollection.json` (May 22) next to `Materials/_pagetype.json` (May 23) — orphan from an early flatlayout-4.2 wrong-sidecar bug; subsequent corrected runs wrote the right one but never cleaned up the orphan. New tests: `scan silently classifies dual-sidecar folders as flat (cleanup at apply)`, `apply deletes co-located per-kind sidecar orphan`.

5. **`5f0e11d` chore(adopter): silence 'var unchanged never mutated' warning.** One-line `var` → `let` cleanup. Cosmetic.

**Data-state confirmation:** Nathan's real nexus migrated successfully — `/Users/nathantaichman/The Nexus/` is flat with all 8 vaults (`Archives` / `Assets` / `Claude` / `Databases` / `Knowledge` / `Materials` / `Pommora` / `Systems`) at root, plus `Tasks/` + `Events/` singletons carrying their sidecars. Flat layout verified end-to-end on production data. Two inert collision-suffixed artifacts (`Tasks.20260523-224558-760F/`, `Events.20260523-224558-46F1/`) sit alongside the authoritative singletons — left for Nathan to delete manually if confirmed empty.

#### Flat-Layout refactor (2026-05-23; tag `flatlayout`)

V0.3.0 refinement on top of ParadigmV2. Drops the `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/` wrapper folders — Page Types / Item Types / Tasks singleton / Events singleton now live at the nexus root, classified by sidecar filename. Ships between `paradigmV2` and v0.3.0; lands before v0.3.0 Properties because Properties' schema-editing operates on these sidecar files. Plan: `// Planning//v0.3.0-Flat-Layout-Plan.md`.

**13 locked decisions:**

1. Wrapper folders disappear — no `<nexus>/Pages/`, no `<nexus>/Items/`, no `<nexus>/Agenda/`; Types live at root.
2. Six per-kind sidecar filenames replace the unified `_schema.json`.
3. Asymmetric `config` suffix on Agenda is intentional — `.task.json` / `.event.json` entity extensions would clash with bare `_task.json`.
4. Swift struct names unchanged from ParadigmV2 — `PageType` / `PageCollection` / `ItemType` / `ItemCollection` / `AgendaTask` / `AgendaEvent` stay.
5. Agenda stays singleton via sidecar-driven discovery — folder rename via Finder Just Works.
6. Sidebar grouping reads sidecar filename, not folder location.
7. Adopter handles FOUR input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat); mixed states tolerated per-folder.
8. Pathological case policy: best-effort + log warnings; first-found wins on duplicate sidecars; timestamp-discriminator suffix on collision.
9. Tasks/Events folders eagerly created on launch (current behavior preserved).
10. Agenda collapse is EventKit-aligned, not just structural — `EKEvent` and `EKReminder` are peer types.
11. Adopter atomicity: best-effort + idempotent; no two-phase transaction; re-launch picks up where it left off.
12. Documentation ships FIRST (Phase 1, before code) so Phase 2–6 subagents read the target spec cleanly.
13. Phase 1 → Phase 2 gated on Nathan's explicit "proceed" signal (remote-review pattern).

**Six per-kind sidecar filenames:** `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`.

**Wrapper folders dropped:** `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. All operational containers now at nexus root.

**Adopter:** handles four input shapes — fresh (content-sniff), legacy v0.2 (`_vault.json` / `_collection.json` in-place rename), paradigmV2 wrapper (unwrap + sidecar rename), already-flat (no-op). Legacy `_vault.json` / `_collection.json` orphans co-located with new sidecars are cleaned up. `.DS_Store`-tolerant empty-wrapper detection — wrappers containing only macOS system-noise files (`.DS_Store`, `Icon\r`, `.localized`) count as empty for deletion. Mixed input shapes coexist; per-folder failures don't block the rest.

**Per-side sidebar section defaults:** "Vaults" (Pages-side) / "Types" (Items-side) — locked UI-divergence rule. Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". All renameable via Settings.

**Agenda discovery:** sidecar-driven — Tasks/Events folders renameable via Finder; discovery walks root for any folder carrying `_taskconfig.json` or `_eventconfig.json`. Multi-folder pathological case: first-found wins with warning logged.

**Build status:** green. **Test count: 363 passing at ship** (up from 358 at flatlayout start).

**Phase-by-phase commit ranges:**
- Phase 1 — Docs: `711d570` 1.1 root, `ad59dec` 1.2 Features, `e29f7e3` 1.3 Guidelines [parallel-session anomaly: edits to `Paradigm-Decisions.md` + `Symbols.md` landed in the editor-refactor commit `e29f7e3` instead of a dedicated `flatlayout/1.3` commit — content correct, metadata bundled with editor work], `2e78503` 1.4 Planning, `735a7a9` planning reorganization + carry-forward cleanup, `42c4ce5` mirror-to-Nexus push.
- Phase 2 — NexusPaths: `f39f541` 2.1 add per-kind sidecar constants, `ffc42ee` 2.2 flatten PageType + PageCollection paths, `da744ab` 2.2.1 sidebar labels follow-up, `6f1add8` 2.3 flatten ItemType + ItemCollection paths, `d4c8a6c` 2.4 Agenda sidecar-driven discovery.
- Phase 3 — Managers: `97eb523` 3.1 PageTypeManager walks root, `d2061f4` 3.3 ContentManagers per-kind sidecars, `d3825c3` 3.5 OrderPersister branches per-side + drop `PageType.itemOrder`; 3.2 (ItemTypeManager) + 3.4 (Agenda managers) verified clean — no changes required beyond Phase 2.
- Phase 4 — Adopter: `f0833f6` 4.1+4.2 combined (scan four shapes + apply best-effort + idempotent + legacy-orphan cleanup), `464faf3` 4.3 drop wrapper helpers + `schemaSidecarFilename` + `reservedTopLevelFolderNames`, `35108d1` 4.4 AdoptionPreviewView warnings + summary.
- Phase 5 — Tests: `fa6b1c0` 5.1 NexusPathsTests rewrite, `249beff` 5.2 NexusAdopterTests four-shapes coverage.
- Phase 6 — Ship: `5ceca94` 6.2 Handoff + History ship entry, `f2d42fe` 6.3 swift-format auto-fixes for lint gate (line-length wraps + import dedupe + `fileprivate` hoist), plus a 6.3 doc-sync fixup — tag `flatlayout` lands on the doc-sync fixup at the tip of the Phase 6 ship cluster. 6.1 grep sweep was a no-op (production code already clean; legitimate `_schema.json` references inside NexusAdopterTests fixtures preserved per spec).

**Outstanding manual step:** Nathan's nexus migration (backup + adopt + verify on real Nexus at `/Users/nathantaichman/The Nexus/`). Engineering ships in flatlayout Phase 4; user-side adoption is one click on next launch — preview describes the migration, apply executes it, idempotent if interrupted.

#### ParadigmV2 — Operational-layer domain model refactor (2026-05-22 plan; SHIPPED 2026-05-23, tag `paradigmV2`)

Vault becomes Pages-only as Page Type; Item Type introduced as parallel Items-side container; Page Collection (Pages) + Item Collection (Items) as parallel organizational sub-folders. AgendaItem split into AgendaTask + AgendaEvent (matching EKReminder + EKEvent). Sub-topics renamed to Projects. Schema sidecars unified to `_schema.json` across all typed containers. On-disk wrapper folders introduced: `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. UI label divergence locked: Pages-side defaults to "Vault" + "Collection"; Items-side defaults to "Type" + "Set"; renameable via Settings. Settings scaffold (`.nexus/settings.json` + `SettingsManager` + label wiring across UI) lays groundwork for v0.6.0 Settings UI. New paradigm rule: "Pommora" prohibited in on-disk schemas + Swift namespace qualifications. Retires `Pommora.Collection` quirk #6. Plan: `// Planning//ParadigmV2.md`.

**Locked phase sequence (11 phases):** 1) Doc rewrites → 2) PageType + PageCollection renames + `_schema.json` sidecar → 3) Subtopic → Project rename → 4) AgendaItem split → 5) New ItemType + ItemCollection subsystem → 6) Pages/Items/Agenda wrapper folders + NexusAdopter → 7) Settings scaffold → 8) Sidebar / Detail / Sheet UI restructure → 9) Tests consolidation + v0.3.0 Properties spec reconciliation → 10) Nathan's user-data migration (one-shot script) → 11) Cleanup + Framework reconciliation + ship (tag `paradigmV2`).

**Execution status (2026-05-23):** **SHIPPED.** Tag `paradigmV2` pushed to origin at commit `36d48c8`. All 11 phases complete. Build green, 358 tests passing (baseline 252; +106 across Phases 4–9). Subagent-driven dispatch: each phase ships green standalone via stub-and-progressively-replace (quirk #8). Phase 2/3/4 fanned out in parallel since they touched disjoint files; Phase 5 used wave-based dispatch (5.1+5.2 → 5.3+5.4+5.5 → 5.6); Phases 7 + 8 followed the same wave pattern. **Fix-forward at `2b8ade8` pulls Phase 10's data-migration scope into NexusAdopter** — legacy root-level Vault folders are classified by content sniff (`.md` → Pages-side; user `.json` → Items-side; empty → default Pages-side) and moved into the appropriate wrapper at `apply()`, with collision handling + fresh-sidecar generation for bare folders. Phase 10 simplified to "backup + run adoption + verify" — engineering shipped, Nathan's manual step (adopt his real nexus) remains open whenever he chooses. Phase 11 closed the ship: final grep sweep cleaned 5 stale type-description docstrings; Framework.md `Current Focus` flipped from "IN FLIGHT" to "SHIPPED"; tag annotated + pushed.

**Phase-by-phase commit ranges:**
- Phase 1 — Docs: `e6ddc04`
- Phase 2 — PageType + PageCollection renames: `b86ddf0` → `2da6d5f` → `aba8f0a` → `a0179d1` → `aeb9a35` (+ auto-heal `4df8188`)
- Phase 3 — Subtopic → Project: `1e1fe77` → `1630586`
- Phase 4 — AgendaItem split: `5e5b225` → `4a0d88c` → `80e326b` → `a4b497f`
- Phase 5 — Items-side subsystem: `2e904ec` → `8c05cc3` → `d07d654` → `e4aa1e5` → `1b052bb` → `5dcbb95`
- Phase 6 — Wrapper folders + adopter: `2eba366` → `fe277c9` → `2686799` + fix-forward `2b8ade8`
- Phase 7 — Settings scaffold: `331f0e2` → `aad27d6` → `fc9903e` → `6e8349e` → `e299587` → `63fb39d` → `207c3ee` (+ UI fix `7f491f7`)
- Phase 8 — Sidebar / Detail / Sheet UI restructure: `e976bb4` → `9853121` → `053abe0` → `0bb58e1`
- Phase 9 — Tests audit + Properties plan re-derive + Handoff/History sync: `54b136b` → `cb97ae2` → `2b1a1c4`
- Phase 11 — Grep-sweep stale docstrings + Framework reconciliation + tag push: `36d48c8` + tag `paradigmV2`

**v0.3.0 Properties plan re-derived** (Task 9.2, commit `cb97ae2`). The original implementation plan at `Planning/v0.3.0-Properties-implementation.md` is now archived under `Planning/Superseded/`; the conceptual WHAT lives at `Planning/v0.3.0-Properties-spec.md`; the post-ParadigmV2 HOW lives at `Planning/v0.3.0-Properties-plan.md` (675 lines, 5 phases A–E, `ItemTypeSettingsSheet` locked to ship at v0.3.0 alongside `PageTypeSettingsSheet`).

**UI tint-cascade regression caught during Phase 7.5 ship.** `.tint(currentAccent)` applied to `ContentView`'s `NavigationSplitView` cascaded the accent color into the `.borderless` "New Collection" button in `PageTypeDetailView`'s footer. Fixed with `.foregroundStyle(.primary)` after `.buttonStyle(.borderless)` — keeps the borderless style but opts out of tint inheritance. Same pattern applies to any other inline button that should NOT inherit the accent.

#### Session 15B (parallel) — 2026-05-21 (Blockquote chrome — v0.2.7.5; visual TBD)

Concurrent with Session 15's drag-reorder work; engine-only scope. Blockquote rendering rewritten from flat `.backgroundColor` + 20pt indent to a renderer-drawn rounded card + continuous vertical accent bar, using the always-show overlay pattern (same as v0.2.7.4 bullet glyph + task checkbox; no caret-aware service).

**Hidden `>` syntax + activation gate.** `> ` (marker + space/tab) is the activation trigger; bare `>` doesn't fire either the renderer chrome or the marker collapse (matches list UX where `-` alone doesn't activate until `- `). `applyMarkerCollapse(in:)` on the supplemental styler walks each line in the blockquote NSRange and applies `font: 0.1pt + foregroundColor: .clear` to `>` + trailing whitespace only when the gate matches — mirrors `visitTable`'s pipe-collapse pattern.

**Renderer-drawn card.** `drawBlockquoteCard(at:in:)` in `MarkdownTextLayoutFragment` draws a rounded `CGPath` fill at `NSColor.tertiarySystemFill` (system-native intensity). The styler no longer emits `.backgroundColor` — moving the fill to the renderer is what makes corner rounding possible (attribute-emitted backgrounds are flat rects with no shape control). New `BlockquotePosition` enum (`.only` / `.first` / `.middle` / `.last`) drives selective corner rounding so multi-paragraph quotes butt-joint into one visually-contiguous block. Position computed via neighbor-line peeks for `> ` start.

**Continuous vertical bar.** 4pt wide pill at `NSColor.secondaryLabelColor`. Bar Y-extent matches card exactly (both inflated by `cornerRadius = 6pt` on rounded ends so the bar extends slightly above/below the body text). `paragraphSpacing = 0` + `paragraphSpacingBefore = 0` between consecutive quote paragraphs so per-fragment bar segments butt-joint flat across multi-line quotes without seams.

**Line-height floor.** `paragraph.minimumLineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)` forces body line height — without it, a `> ` line with no content yet has only font-0.1 marker chars on it → natural line collapse to ~1pt. The floor keeps the line tall enough to type into AND lets the chrome have proper vertical extent before content arrives.

**Enter/Shift+Enter semantics match list convention.** Plain Enter on a `> foo` line inserts `\n<prefix>` (continues the quote, preserving leading indent — new `blockquoteMarkerRegex` powers detection); Shift+Enter inserts plain `\n` (exits the quote). Mirrors how plain Enter continues lists and Shift+Enter exits.

**v0.2.7.5 caveat:** the horizontal positioning of the card highlight relative to the bar still has a visual mismatch — the card appears to start at the body text rather than extending into the hidden `>` syntax area. Suspected to be either a bar-pill-radius (2pt) vs card-corner-radius (6pt) mismatch causing a visible 2pt gap at the rounded corners, OR a card-fill alpha visibility issue. Shipped as-is, follow-up next session.

**Files (this session — engine package only):**
- `External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift` — `visitBlockQuote` rewrite + `applyMarkerCollapse(in:)`.
- `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift` — `import Markdown`, `hasBlockquoteMarker`, `BlockquotePosition` + `blockquotePosition`, `drawBlockquoteCard(at:in:)`, `makeSelectiveRoundedRect(_:radius:roundTop:roundBottom:)`, `renderingSurfaceBounds` extension.
- `External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift` — `blockquoteMarkerRegex`, plain-Enter blockquote-continue branch.
- `External/MarkdownEngine/NOTICE.md` — v0.2.7.5 entries.

**Decisions locked (this session):**

10. **Blockquote uses always-show overlay, NOT dynamic-syntax.** Per Nathan: "the always-show is how it currently works; we have no intent on changing that." Per L14 (`// Guidelines//Markdown.md`): always-show beats caret-aware reveal for non-interactive markers. Locked at `// Guidelines//Markdown.md` §9.10.
11. **Plain Enter continues quotes; Shift+Enter exits.** Mirrors list convention. Both behaviors live in `MarkdownListHandler.handleInsertion`'s `\n` branch.

#### Session 14 (parallel) — 2026-05-21 (Editor polish bundled into v0.2.7.4)

A parallel session shipped four small editor wins folded into the v0.2.7.4 ship.

**Bullet glyph substitution shipped.** Closes the Session 13 deferred item. Lines starting with `- ` render `•` via `MarkdownTextLayoutFragment.drawDashBulletGlyph` overlay (always-on, no caret-reveal — same UX guarantee as task checkboxes). The source dash stays in storage as portable CommonMark `- item` for cross-tool readability; the styler hides only its color (`NSColor.clear` while preserving natural width). Only `-` triggers — `*` / `+` / `•` literal markers render as-is. Pixel-aligned draw via `backingScaleFactor` so the bullet doesn't vanish on fractional Y positions (the Session 13 failure mode).

**Task-list shorthand `-[]` / `-[x]`.** Both forms now match alongside the GFM `- [ ]` / `- [x]` form. Regex updated in two places (`MarkdownStyler.taskListRegex` + `MarkdownLists.listRegex` + `bulletListPattern`): spacer group is zero-or-more (was one-or-more), inner-bracket content is `[ xX]?` (was `[ xX]`). Marker collapse: the leading `-` plus any whitespace before the `[` shrinks to font 0.1pt + clear color so the drawn checkbox glyph is the only visible marker prefix (the `[...]` brackets themselves stay at body font — the checkbox draw reads `font.pointSize` from the `[` to compute its size, so collapsing the brackets would make the box render near-zero).

**Bracket auto-pair guard.** Typing `[` only fires the `[` → `[|]` auto-pair when the preceding char is whitespace (space / tab / newline) or the cursor is at line start. Lets the Pommora `-[]` flow without the auto-pair inserting a `]` between `-` and `[`. Prose-link case (`text [link](url)`) still auto-pairs. Implementation in [`MarkdownLists.handleListInsertion`](../External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift) — `shouldAutoPair = (insertionLocation == 0) || prevChar in {" ", "\t", "\n"}`.

**Arrow auto-format extended.** Closes the Session 13 known bug ("typed `<-` and `<->` don't fire on input — only on paste"). Two new cases added to the `>` keypress handler: (A) chained `<-` → `←` then `>` extends `←` → `↔`; (B) pasted `<-` still-literal in buffer, `>` does a combined two-char replace `<-` → `↔`. The existing `->` → `→` case unchanged.

**Code colors.** `MarkdownStyler` now applies `.foregroundColor: NSColor.systemRed.withAlphaComponent(0.85)` to both `.codeBlock` and `.inlineCode` token attributes. `PlainTextSyntaxHighlighter.backgroundColor()` returns `NSColor.quaternaryLabelColor` — semantic system fill, adapts light↔dark, has built-in subtle alpha. Replaces the previous `textBackgroundColor.withAlphaComponent(0)` (effectively invisible).

**Files (parallel session):** `MarkdownStyler.swift`, `MarkdownListHandler.swift`, `MarkdownDetection.swift` (added `isDashBulletLine` mirroring `isThematicBreakLine`'s three-stage pattern, with regex-only Stage 2 since CommonMark's space-after-marker requirement is encoded in the bullet regex), `MarkdownTextLayoutFragment.swift` (added `hasDashBulletMarker` + `dashBulletMarkerDocumentLocation` + `drawDashBulletGlyph` + `renderingSurfaceBounds` extension for invalidation), `MarkdownEditorServices.swift` (`PlainTextSyntaxHighlighter.backgroundColor()`).

**Decisions locked:**

7. **Portable-source-with-overlay is the locked pattern for dash bullets** — same as HR. Source on disk is portable CommonMark; the visual glyph is drawn by the layout fragment at render time. No source mutation.
8. **`-` is the only dash-bullet trigger.** `*`, `+`, and legacy `•` markers render literally. Single-trigger keeps the styler-vs-renderer agreement contract simple.
9. **Bracket auto-pair requires a word boundary on the left.** Auto-pair fires only after whitespace or at line start. Lets compact task syntax (`-[]`) coexist with prose-link auto-pair.

#### Session 14 (continued) — 2026-05-21 (HR jitter on large files — root-cause + two-phase fix)

Editor exhibited two distinct jitter symptoms on large documents: (a) general jitter during cursor placement and selection drag, and (b) a vertical "auto-adjust" of the line when the caret entered or left an HR paragraph. Systematic debugging located two independent root causes, both in the Session 12 HR dynamic-syntax pattern. Same UX preserved.

**Phase 4a — selection-scope.** `NativeTextViewCoordinator.syncHRVisibility` walked the **entire document** on every `textViewDidChangeSelection`, calling `NSString.lineRange(for:)` + `substring(with:)` + an attribute read on every paragraph and Stage-1 + Stage-2 `Markdown.Document(parsing:)` AST parse on any HR-shaped paragraph. The comment claimed "microseconds for typical docs" — true for small files, but on a 1000-paragraph file the cost is ~1ms per caret tick and mouse-drag selection fires this 60+ times per second.

The HR state of paragraphs N..end can only change when the caret crosses into or out of a specific paragraph — every other paragraph's hidden/revealed state is already correct from the last full walk (initial load + each edit cycle). Added a scoped overload `syncHRVisibility(in:textView:scopedTo:)` that walks only a supplied list of paragraph ranges; `textViewDidChangeSelection` now passes `{currentCaretParagraph, priorCaretParagraph}`. Restyle paths (`restyleTextView`, `rebuildTextStorageAndStyle`) keep the full walk because edits can introduce or remove HRs anywhere. Shared `applyHRSync` + `makeHRStylingContext` extracted so the two variants cannot drift. The `priorCaretLocation` must be captured BEFORE `previousCaretLocation` is overwritten at the bottom of `textViewDidChangeSelection`; a local variable at the top of the function handles this. O(N) per-caret-tick walk replaced with O(1).

**Phase 4b — layout-constancy.** Caret entering an HR paragraph caused a visible vertical jump because the locked design swapped the dashes from `NSFont.systemFont(ofSize: 0.1)` (line height ~0.1pt) to `bodyFont` (~21pt) AND swapped the paragraph style from `hrParaStyle` (paragraphSpacingBefore = paragraphSpacing = 16) to `baseParagraphStyle` (zero spacing). Net paragraph height collapsed by ~11pt on enter and reflowed on leave.

Unified the two states: dashes always render at `bodyFont`, only the foreground color toggles (body text color when caret is in, `NSColor.clear` when out). Same paragraph style in both states, computed once per sync pass from the base style with `paragraphSpacingBefore = paragraphSpacing = max(0, 16 - bodyLineHeight / 2)` — preserves Session 12's perceived 16pt visual margin around the drawn rule line at any font size while keeping total paragraph height constant. Replaced separate `applyHRHiding` / `revealHRDashes` with a single `applyHRDashAttributes(in:paragraphRange:bodyFont:foregroundColor:)`. The drawn rule (in `MarkdownTextLayoutFragment.drawThematicBreak`) sits at the line's typographic midY, which is now identical in both states — so the rule's geometric position relative to the dashes is unchanged whether they're visible or invisible.

**Files:** [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift) (scoped overload + unified hidden/revealed paths + computed paragraph spacing); [`NativeTextViewCoordinator+TextDelegate.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift) (capture `priorCaretLocation` before overwrite; switch caret-only path to scoped sync; skip when `tokensChanged` since `restyleTextView` already did a full walk).

**Decisions locked:**

5. **HR caret-aware reveal/hide must not cause vertical layout change.** Both states share line metrics + paragraph spacing; only dash color differs. Computed spacing `max(0, 16 - bodyLineHeight / 2)` keeps the ~16pt visual margin invariant at any font size.
6. **Dynamic-syntax services must scope per-caret-move work.** `syncHRVisibility` on `textViewDidChangeSelection` is the canonical example — only the prior + current caret paragraphs need touching. Full walks stay on `restyleTextView` and `rebuildTextStorageAndStyle` for events that can add/remove the construct anywhere.

Build green; 244 unit tests passing (one pre-existing full-suite flake on `debounceCoalescesRapidEdits` unrelated to TextKit); lint exit 0.

#### Session 14 — 2026-05-21 (v0.2.7.4 Nexus folder adoption SHIPPED)

Obsidian-parity "open folder as Nexus." Both Nexus-open paths (`openPicked` from menu, `openExisting` from saved bookmark) now run `NexusAdopter.scan` after identity is established and present a preview-and-confirm sheet listing top-level folders → Vaults and direct sub-folders → Collections. Excludes only `.`/`_`-prefixed, `node_modules`, `.trash`, `Agenda`. Idempotent — fully-adopted Nexuses produce an empty plan and skip the sheet silently. Re-runs on every open catch newly-added folders (the indexer is the source of truth, not first-launch state).

`PageFile.loadLenient(from:nexusRoot:)` accepts `.md` files without Pommora frontmatter — synthesizes a stable `id` from `"adopted-" + sha256(relativePath).prefix(16)`, defaults tier/properties to empty, uses file `creationDate` for `created_at`. Critical invariant: does NOT write back. Files stay byte-identical until the user actually edits and saves. Used by both `ContentManager.loadAll(for:)` and the editor host (`PageEditorHost.swift:74`) — anything that surfaces in the sidebar also opens. `Filesystem.descendantFiles` makes Content discovery recursive; depth-≥2 folders aren't Collections but their files roll up to the nearest Collection ancestor.

`NexusManager.isIndexing` + `IndexingHUD` overlay in the sidebar give visible feedback during the scan. `pendingAdoption: AdoptionPlan?` + `withCheckedContinuation` route the sheet's user decision back into the async open flow; sheet auto-dismiss (Esc / click-outside) handled via `.sheet(item:onDismiss:)` calling idempotent `resolveAdoption(false)`.

**Architecture cross-check via Context7.** Pommora's Vault + `.nexus/` structure verified identical to Obsidian's Vault + `.obsidian/` shape. The one principled divergence: Vaults need `_vault.json` and Collections need `_collection.json` because Pommora has a per-Vault property schema concept Obsidian lacks. The indexer creates those sidecars on existing folders so the user doesn't have to.

**Files:** `NexusAdopter.swift` (new), `AdoptionPreviewView.swift` (new), `NexusManager.swift` (open hooks), `Filesystem.swift` (`descendantFiles` + `writeMetadataIntoExistingFolder`), `PageFile.swift` (lenient path), `ContentManager.swift` (recursive load + lenient), `PageEditorHost.swift:74` (load swap), `ContentView.swift` (sheet + HUD). Tests: `NexusAdopterTests` (11) + `PageFileLenientTests` (6); full suite 244 passing, lint exit 0.

**Cleanup pass post-implementation:** auto-dismiss continuation hang fixed; redundant `String.StringInterpolation` extension removed; manual `Equatable` on `AdoptionError` replaced with auto-synth; duplicate `childFolders` enumeration in `scan` merged; `apply`'s vault-id cache populated inline as we write instead of via a separate reload pass.

**Decisions locked:**

1. **Adoption runs on every open**, not just first-time init. Re-runs are idempotent and catch newly-added top-level folders (Obsidian-parity).
2. **Existing `.md` files stay byte-identical** until the user edits — lenient load synthesizes the id in memory only. Adopting a folder that's also an Obsidian vault doesn't mutate any notes.
3. **2-level structural depth** (Vault > Collection) preserved from the locked domain model; deeper sub-folders aren't Collections but their Markdown files roll up to the nearest Collection. No flattening of the model.
4. **Agenda stays as a sibling of Vaults** at `<nexus>/Agenda/`, not inside `.nexus/`. Files-are-canonical principle: user data lives at the user-visible root.

#### Session 13 — 2026-05-20 (v0.2.7.2 Lists shipped)

Lists rewrite: space styles immediately (styler-driven, no source mutation), Enter continues with the next marker, Shift+Enter exits with a plain `\n`, bare `-` / `1.` + Enter initializes. Source on disk is portable CommonMark (`- item` / `* item` / `+ item` / `1. item`) — pre-v0.2.7.2 `\t• ` engine-only syntax dropped (legacy files render via back-compat regex). Visual indent via styler paragraphStyle without source `\t`. Bullet glyph substitution (`-` → `•` visually) attempted + reverted (overlay produced invisible bullets); deferred as non-blocking cosmetic.

Pivots: Case 2 (empty-item exit) + Case 3 (mid-line continuation indent) dropped — Enter always creates a new list item; Shift+Enter is the only exit. Shift+Enter detection moved from `doCommandBy` (only fires on Ctrl+\) to a modifier-flag check at the top of `shouldChangeText`'s `\n` branch.

Bug noted: typed `<-` / `<->` don't transform to `←` / `↔` though typed `->` → `→` works (pasted versions render correctly).

Architecture + 4 new lessons in `Features/PageEditor.md → Dynamic-syntax pattern`. Deferred: bullet glyph, blockquote rendering, code & quote `Enter}` auto-completion, code-block red-text bug, arrow auto-format gap.

#### Session 12 — 2026-05-20 (v0.2.7.2 HR / divider SHIPPED via Obsidian-style dynamic syntax; Blockquote + Tables deferred)

**HR shipped** via a different architecture than the locked spec. Original plan attempted the locked design (custom `.pommoraThematicBreak` attribute + always-hidden dashes + cursor-out push + smart-backspace handlers); after four cascading bugs across two execution rounds, reverted to v0.2.7.1 baseline and replanned. Replanned design uses **Obsidian/Typora-style dynamic syntax** — caret on line shows `---`, caret off line hides dashes and draws the horizontal line. Establishes architecture for paragraph-level dynamic-syntax constructs. Full architecture + 8 lessons in `Features/PageEditor.md → Dynamic-syntax pattern`.

**Three engine files changed + one new file:** `MarkdownTextLayoutFragment.swift` — added `import Markdown`, AST-backed `hasThematicBreak` (Stage 0 code-block guard + Stage 1 prefilter + Stage 2 AST parse), `caretIsInFragment` (paragraph-start identity), rewrote `drawThematicBreak` with raw `separatorColor` + container-minus-padding width + stable `textLineFragments.first.typographicBounds.midY` Y anchor, wired into `draw(at:in:)`, extended `renderingSurfaceBounds` tightly (±3.5pt). `AppleASTSupplementalStyler.swift` — `visitThematicBreak` reduced to no-op (service is sole writer of HR attributes). `NativeTextViewCoordinator.swift` — added `isSyncingHRVisibility` reentry flag. `NativeTextViewCoordinator+HRVisibility.swift` (NEW) — caret-awareness service: walks document on every selection-change + post-restyle, applies `font 0.1 + clear color + paragraphSpacing 16/16` when caret is OUT of HR paragraph, restores body styling when caret is IN. Wired into `textViewDidChangeSelection` + `restyleTextView` + `rebuildTextStorageAndStyle`. `MarkdownInputHandler.swift` — preserved Nathan's `()` auto-pair (no HR-related additions; auto-transform DROPPED). `MarkdownListHandler.swift` — legacy HR expansion (`---` → 100-dash string on Enter) removed; incompatible with overlay approach.

**Pivots from locked plan:** 6-change plan reduced to 3 (`caretIsInFragment` + dynamic-syntax eliminated cursor-out push, smart-backspace handler, and caret-policy workaround in `NativeTextView+CaretWorkarounds`); auto-transform on 3rd dash + 4th-dash swallow DROPPED (per Nathan: Enter is natural trigger via dynamic syntax + CommonMark parsing of `---\n`); paragraphSpacing 16/16 (vs plan's 24/24) per Nathan; setext-underline guard added then removed — contradicted CLAUDE.md's "Pommora removed Setext H2 support" (`B\n---` must always render as HR per Obsidian/Typora); `.pommoraThematicBreak` attribute key kept as dead code (optional cleanup).

**Four hotfixes during execution:** (1) removed legacy `MarkdownListHandler` HR expansion (lines 245-267); (2) fixed renderer/service detection disagreement — moved setext + code-block guards into shared three-stage service check; (3) dropped setext guards from BOTH detectors per Nathan's clarification; (4) attempted `.rounded()` pixel-snap for first-HR-dimness; did NOT resolve; reverted (lesson #8: revert speculative fixes; don't pile on).

**Known caveat:** First HR renders slightly dimmer than subsequent HRs — likely sub-pixel anti-aliasing from first paragraph's fractional Y position. `.rounded()` pixel-snap didn't resolve. Documented in PageEditor.md; next investigation should test `NSScreen.backingScaleFactor`-aware half-pixel snap or explicit anti-aliasing disable.

**Deferred:** Blockquote (Phase 1) → next session, reuses dynamic-syntax architecture (Apple-Calendar-event-card target preserved); Tables (Phase 3) → "ASAP but not immediate" per Nathan (estimate revised to 10-15h after divider's 4h actual vs planned 45min); right-click "Insert HR" → future patch.

**Open follow-ups Nathan flagged:** (1) Lists improvements — Enter on bare `-`/`*`/`1.` should commit as list item (currently only space triggers); Shift+Space inserts new list item below at same nesting. (2) Blockquote — see above; reuses dynamic-syntax pattern.

Plan files now stale; Page-Editor-Plan.md's HR portion was scrubbed pre-execution. Post-ship architecture lives in PageEditor.md `Dynamic-syntax pattern`, not the plan file.

#### Session 11 — 2026-05-20 (v0.2.7.2 page editor fixes plan LOCKED — Round 5 + Round 6 refinement)

**No code commits.** Planning-only via Claude.ai mobile (RC). Plan sharpened across two refinement rounds. v0.2.7.1 NavDropdown unchanged on `main` (tagged + pushed). Plan files 3-way sync: canonical at `~//.claude//plans//frolicking-enchanting-perlis.md`, Studio mirror at `.claude//Planning//Page-Editor-Plan.md`, Nexus mirror at `//The Nexus//Pommora//Planning//Page-Editor-Plan.md`.

**Round 5 — research-driven sharpening:**

1. **NSTextTable rejected as Apple-native table-rendering alternative.** Via Context7 + research agents: `NSTextTable` / `NSTextBlock` / `NSTextTableBlock` exist since OS X 10.3 but never promoted to TextKit 2. Apple's TextEdit silently downgrades to TextKit 1 on table insertion (Marcin Krzyzanowski, "TextKit 2: The Promised Land," Aug 2025 — via Michael Tsai). Apple Notes uses a custom protobuf document model, NOT NSTextTable. Adopting NSTextTable would forfeit Writing Tools (15.1+), Look Up / Translate, spell-check, IME, dynamic system colors. **Core Graphics overlay drawn in `MarkdownTextLayoutFragment.draw` IS the 2026 Apple-native pattern.** Rationale in plan's Architecture decisions table.

2. **HR cursor-atom behavior added (Fix 2d).** `---` source line stays in storage (needed for swift-markdown's ThematicBreak parse) but caret must never plant inside. `textViewDidChangeSelection` push-out (direction-aware, mirrors NSTextAttachment caret-skip); arrow keys skip past; smart-backspace from line below deletes `---\n` in one keystroke. Both interceptors guard against `isProgrammaticEdit == true` so Stage 3.C table-cell splices don't trip them. Apple Notes parity. Phase 2 estimate ~30min → ~45min.

3. **Stage 3.D — structural context menu added** per Nathan's "add column / add row should be on the context menu and shouldn't open the popup." Right-click in `.pommoraTable` range surfaces "Add Row Above / Below" + "Add Column Left / Right" → in-place AST splice via new `TableStructureRewriter` (Apple `MarkupRewriter`) + `Markup.format()` GFM emission + `performEditingTransaction`. Does NOT open popover (matches Apple Numbers/Pages/Notes). Row insert preserves widths (columnCount unchanged → `pommora_table_widths` fingerprint hits); column insert resets to auto (columnCount changes → misses). Remove row/column deferred.

**Round 6 — visual + UX corrections:**

4. **Popover cell styling spec corrected against Apple docs.** Gemini's 4-point recipe verified via Context7 + `swiftui-expert-skill`. **2 of 4 needed correction, 4 pieces missing.** Locked spec for each `cellField` in the popover Grid:
   - `.textFieldStyle(.plain) + .focusEffectDisabled()` — `.plain` strips bg + border but NOT the focus ring (separate AppKit concern); need `.focusEffectDisabled()` explicitly.
   - `.padding (inner) → .frame (outer)` — SwiftUI modifier order applies outer-in; padding-then-frame puts padding INSIDE the cell-sized frame (correct).
   - `.contentShape(Rectangle())` — without it, taps on transparent expanded-frame area don't register (SwiftUI hit-tests intrinsic content, not explicit frame).
   - `.onTapGesture { focusedCell = ... }` on the wrapper — expanded hit area catches tap but doesn't auto-route focus to embedded TextField; wrapper-level routing is safe.
   - `TextField(..., axis: .vertical)` with `.onKeyPress(.return) { return .handled }` (macOS 14+) — `.onSubmit` doesn't fire for `axis: .vertical` (newline-on-Return by-design).
   - Beyond Gemini: per-column `.multilineTextAlignment` from GFM `table.columnAlignments`; `lineLimit(1...10)` soft cap; 1pt accent `.overlay` focus border; `NSCursor.iBeam` push/pop on hover.

5. **Blockquote target swapped: "Apple Notes minimal bar" → Apple Calendar event-card chrome.** Nathan supplied a Calendar Today-widget event-card screenshot. Grey rounded-rect card (6pt corner radius, `Color.primary.opacity(0.06)` fill — `NSColor.labelColor.withAlphaComponent(0.06)`) + 3pt `NSColor.separatorColor` bar INSIDE the card at ~4pt inset from leading edge. Multi-line blockquotes use per-fragment corner-rounding (`.only` / `.first` / `.middle` / `.last`) to render as one visually contiguous card. `BlockquoteMetadata { let sourceRange: NSRange }` attribute payload (upgraded from `Bool`) lets each fragment determine position without re-scanning storage. Mirrors `drawCodeBlockBackground`'s CGPath + bg-fill pattern. `paragraphStyle.headIndent = 20` (4pt card-edge → 3pt bar → 13pt clear → text). Aligns plan with `Features/Pages.md` (described it as "Calendar.app event-card pattern" all along). Phase 1 estimate ~25min → ~45min.

6. **Version bumped: v0.2.7.1 → v0.2.7.2 for this plan.** NavDropdown took v0.2.7.1. Sequence: `v0.2.7.0` engine swap (S9) → `v0.2.7.1` NavDropdown (S10) → `v0.2.7.2` page editor fixes. Tables custom grid (was v0.2.7.3) absorbs into v0.2.7.2 Phase 3.

**Plan-only meta:** 24 parallel edits in 3-way plan file sync for blockquote re-spec; ~36 total plan-file edits across Rounds 5+6. All three files byte-identical (modulo Nexus mirror's supersession header). Total estimate ~7.5h across 3 phases / 4 stages (Phase 1 ~45min + Phase 2 ~45min + Phase 3 ~6h). 9 new test suites scoped: `BlockquoteTests`, `HRAutoTransformTests`, `HRCursorAtomTests`, `TableRenderingTests`, `TableColumnWidthTests`, `TablePopoverEditTests`, `TablePopoverCellInteractionTests`, `TableStructureEditTests`, extended `PageFrontmatterTests`. Phase commit cadence: Phase 1 → Phase 2 → Stage 3.A → 3.B → 3.C → 3.D. Each green standalone.

**Doc deltas (no code):** `// Planning//Page-Editor-Plan.md` (Studio), `~//.claude//plans//frolicking-enchanting-perlis.md` (canonical), `//The Nexus//Pommora//Planning//Page-Editor-Plan.md` (Obsidian mirror) — Round 5+6 updates. `Handoff.md` — new "Current State (end of 2026-05-20)" + v0.2.7.2 priority + updated resume prompt. `Framework.md` — patch list reflects v0.2.7.2 plan-locked; Planned section rewritten; cumulative history entry added. `Features//PageEditor.md` — deferred patches table rewritten; v0.2.10 → v0.3.2 wikilinks references; v0.2.9 marked unscheduled. `Features//Pages.md` — stale v0.2.7.2 NavDropdown references corrected to v0.2.7.1 (shipped without the preview-then-expand mechanic). `PommoraPRD.md` — Editor row stack updated (Option 2 hypothetical → Option 1 native TextKit-2 SHIPPED at v0.2.7.0). `CLAUDE.md` Active Version — v0.2.7.2 plan-locked status.

**Tooling used:** Context7 MCP (Apple SwiftUI docs for TextField axis / textFieldStyle / onKeyPress / NSPopover); `swiftui-expert-skill` (text-patterns / focus-patterns / macos-views / latest-apis references); targeted research agents for NSTextTable verdict (Krzyzanowski blog + Apple Forums); plan-file 3-way sync via parallel Edit calls.

---

#### Session 10 (continued) — 2026-05-19 (v0.2.7.1 NavDropdown SHIPPED — simplified + cleaned)

Session 10 second half. Nathan: "this session produced lots of data layers, and code with lots of back-and-forth touch-ups that I'm still unhappy with." The v0.2.7.2 NavDropdown shipped earlier was functional but bloated — 22 commits of UIX iteration on standalone-window chrome + hover-heart favorites that didn't land where Nathan wanted.

**Scope cuts Nathan called for:** (1) remove standalone preview-window machinery entirely — feature-specific window plumbing rots; the real PreviewWindow is a cross-feature primitive (build once, light up per kind); (2) replace hover-heart favorites with right-click "Pin" context menu — rename Favorites → Pinned across class, file, JSON key, UI; (3) mid-session add: detail-view context menus on Page + Item rows inside Vault/Collection views don't work — fix in same patch.

**Commits (8, all on `main`):**
- `4def823` v0.2.7.2.1-a.1 — Strip standalone-window machinery: deleted `EntityRef.swift`, `EntityWindowHost.swift`, `EntityRefTests.swift`, `WindowGroup(for: EntityRef.self)` scene; replaced `SidebarSelection.init?(entityRef:)` with `init?(stateRef:)`; updated `BackForwardButtons` + `NavDropdownButton`; renamed `MainWindowRouter.Intent.expandFromWindow` → `.directNavigation` (`requestExpand` → `requestOpen`); deleted `ContentManager.findPage(byID:vaultManager:)`. **406 deleted, 58 added.**
- `406e585` v0.2.7.2.1-a.2 — Favorites → Pinned rename: `FavoritesManager` → `PinnedManager`, JSON key `favorites` → `pinned` with backward-compat decode (`favoritesLegacy = "favorites"` CodingKey fallback), `AppGlobals.favoritesManager` → `AppGlobals.pinnedManager`, `ContentView.favoritesManager` updated, `NavDropdownButton.PanelMode.favorites` → `.pinned` + `pinnedSnapshot` + `pinnedList` + empty-state "Right-click to pin". Two new `NexusStateTests` cover legacy-key decode + encoder-doesn't-emit-favorites.
- `d524b09` v0.2.7.2.1-a.3 — `EntityRow` rewrite: removed hover-heart Button + `isFavorite` / `favoriteAction`; added `isPinned` / `pinAction`; repurposed `@State hovering` to drive row-background tint (`Color.primary.opacity(0.06)` in 6pt rounded rect); added `.contextMenu { Button("Pin {chip}" | "Unpin {chip}") { pinAction() } }`. NavDropdownButton sites updated.
- `9c96405` v0.2.7.2.1-a.4 — Click model rewire: removed `.onChange(of: selection) { handleOpen }` handlers (single-click was firing open — wrong UX). Single-click only updates List's selection binding (native row highlight). Double-click fires `.onTapGesture(count: 2) { handleOpen(ref) }`.
- `3f768cb` v0.2.7.2.1-b.1 — Detail-view context menus: `VaultDetailView` + `CollectionDetailView` add `.contextMenu` on Page + Item rows with Rename (alert + TextField → `ContentManager.renamePage` / `renameItem` per vault-root vs collection parent), Pin / Unpin {kind} (toggles `AppGlobals.pinnedManager`), Delete (mirrors sidebar no-confirmation pattern). `VaultDetailView` uses `parent(for:)` helper scanning vault-root then collections. **+274 / -10 lines.**
- `68d497e` v0.2.7.2.1-a.5 — Bugfix double-click open: `.onTapGesture(count: 2)` inside SwiftUI List on macOS gets intercepted by NSTableView's selection handler. Switched to `.simultaneousGesture(TapGesture(count: 2))` so gesture coexists with List's row-click. Added Task-based lazy-load fallback in `handleOpen` — when `SidebarSelection(stateRef:)` returns nil for a page (host collection not loaded), walk `vaultManager.vaults` + `contentMgr.loadAll(for:)` retrying at each step.
- `4ad9156` v0.2.7.2.1-a.6 — Bugfix collections + routing: (1) wired `.collection` case in `SidebarSelection.init?(stateRef:)` — leftover `return nil` blocked collection rows from opening; SidebarDetailView already routes `.collection` → CollectionDetailView. (2) Bypassed `AppGlobals.mainWindowRouter` @Observable hop for the dropdown (didn't propagate reliably from popover view host — same root cause as empty-Recents bug). NavDropdownButton gains `onOpen: (SidebarSelection) -> Void`; ContentView passes `{ sel in sidebarSelection = sel }`. Direct @State binding write, reliable across view-host boundaries. MainWindowRouter stays for back/forward.
- (final commit) — v0.2.7.1 ship: doc updates (Handoff / NavDropdown.md / CLAUDE.md Active Version / History entry / session transcript), GitHub CI removed (`.github/workflows/ci.yml` — Nathan: failure emails), new architectural rule at `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` (PreviewWindow primitive ships per kind before any "open in preview" UI for that kind).

**Version note:** committed/tagged `v0.2.7.1` despite chronologically following `v0.2.7.2`. `v0.2.7.2` stays in git history as "first NavDropdown attempt (functional but UIX-deferred)"; v0.2.7.1 is canonical shipped NavDropdown. Planned v0.2.7.1 Page-editor-touch-ups slot shifts to a later patch number.

**Tests:** 226 pass (v0.2.7.2 baseline 227 - 3 deleted EntityRefTests + 2 new NexusStateTests).

**Doc / arch deltas:** `Guidelines/CRUD-Patterns.md` — new "Preview-window prerequisite": PreviewWindow primitive ships per kind before any "open in preview" UI for that kind; CRUD lands independently (deleted EntityWindowHost is the cautionary tale). `Features/NavDropdown.md` — Status v0.2.7.1; version-supersedes note; "Future implementation" with 4 deferred items (preview-window wiring, drag-to-reorder Pinned fix, type-chip removal, segmented-picker polish). `Handoff.md` — full rewrite for v0.2.7.1 close + next priorities (page editor touch-ups / sidebar drag-reorder / v0.3.0 Properties / PreviewWindow primitive). `.github/workflows/ci.yml` deleted.

**Files renamed:** `FavoritesManager.swift` → `PinnedManager.swift`, `FavoritesManagerTests.swift` → `PinnedManagerTests.swift`.

**Files deleted:** `EntityRef.swift`, `EntityWindowHost.swift`, `EntityRefTests.swift`, `ContentManager.findPage(byID:vaultManager:)` (method), `.github/workflows/ci.yml`.

---

#### RC Session — 2026-05-19 (v0.3.0 Properties brainstorm + spec + tighten)

**No code commits.** Docs + planning via Claude.ai mobile (RC). Edits authored in `// The Nexus//Pommora//` mirror first; deployed to `// The Studio//Projects//Project Pommora//.claude//` end of session.

**Shipped (docs only):**
1. **`Planning//v0.3.0-Properties-implementation.md`** (NEW, ~5000 words) — implementation spec grounded in Pommora Swift code (file:line citations to PropertyType / PropertyDefinition / PropertyValue / Vault / PropertyEditorRow / FrontmatterInspector / AgendaSchema). Four phases (model → manager → UI → validation/tests). 14 locked decisions. v0.3.x sub-sequence: .0 Properties / .1 Items pane / .2 Page-wikilinks / .3 SQLite. Estimate 7-10 sessions.
2. **`Planning//v0.3.0-Properties-uncertainty-log.md`** (NEW) — top 5 blockers (PropertyValue Status-vs-Select decode collision; RelationScope migration; multi-file atomic-write recovery; Sendable on new types; missing test coverage); SwiftUI patterns via Context7 (`TableColumnForEach`, `TableColumnCustomization`, `KeyPathComparator`, drag-between-Sections); 7 open design questions; edge cases; 16 new files + 15 modifications + 3 reserved; migration checklist.
3. **`Planning//Roadmap-Reorder-Tier-Model.md`** (NEW) — tier model framing (Tier A polish v0.2.7.x → Tier B foundation v0.3.x-v0.7.0 → Tier C interaction v0.8.0+). Same total work as Framework; cleaner naming.
4. **`Features//Properties.md`** (revised) — 10-type catalog (added Status + Last Edited Time); Status type with EventKit-aligned 3 groups (Upcoming / In Progress / Done); Relation scope rework (Vault/Collection/ContextTier, no anywhere); mandatory dual relations for Vault/Collection; option-move-between-groups; no-inline-option-creation; property icons; Vault Settings sheet as central edit surface.
5. **`Features//Vaults.md`** (revised) — `_vault.json` example with new RelationScope shape + dual config + Status property + default_sort; Vault Settings sheet (6 sections); Vault templates removed; content templates reservation pointer.
6. **`Features//Items.md`** (revised) — v0.5 refs → v0.3.0 / v0.3.1; Item Window redesign retargeted v0.3.1; Item creation surfacing lands v0.3.0.
7. **`Features//Agenda.md`** (revised) — new "Built-in `status` property" with EventKit-aligned groups + sync mapping; schema JSON example updated; migration shim.
8. **`Framework.md`** (revised) — v0.3.x sub-sequence locked; v0.4.0 slimmed to Trash UI + cascade refinements (SQLite + move-strip pulled into v0.3.x); 2026-05-19 cumulative history entry.
9. **`PommoraPRD.md`** (revised) — Property Model rewritten (10 types, Status first-class, paired relations mandatory, no inline option creation, schema editor centralized).
10. **`Sidebar.md`** + **`Domain-Model.md`** (minor) — Vault Settings entry point; Properties section updated with v0.3.0 catalog.

**RC-session locked decisions** (14 in implementation spec): 10-type property catalog (number / checkbox / date / datetime / select / multi-select / URL / relation / **status** / **last edited time**); Status: 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done), group labels renamable, slots structural; relation scope: Vault / Collection / Context-tier, mandatory dual for Vault/Collection; no inline option creation — schema editor + right-click "Edit options…" + "Manage options…" link only; property icons (SF Symbol per property); Vault Settings sheet: 6 sections (3 functional v0.3.0 + 3 placeholders v0.6.0); Collection picker UX: 2-step Vault→Collection at schema time, Collection-grouped at value time; Vault templates REJECTED in favor of post-v1 content templates (storage location + Codable sketch reserved); property names remain key (rename-cascade via SchemaTransaction two-phase commit); no `.anywhere` relation scope; Move-strip pulled v0.4.0 → v0.3.0 (tightly coupled to schema); AgendaSchema migration shim for built-in Status injection on legacy schemas; MultiSelectChips: signature changes to `[SelectOption]` for color rendering, `allowsAddingOptions` flag removed; SchemaEditorRouter `@Observable` for shortcut routing to Vault Settings at specific property.

**Tooling used:** Context7 MCP (Notion API + Apple SwiftUI docs); Explore agent inventory of Pommora Swift code; cross-reference against existing Pommora docs.

---

#### Session 9 — 2026-05-18 (continued — **v0.2.7.0 SHIPPED + PUSHED to origin in 10 commits**)

Executed Session-8 plan + live-feedback iteration with Nathan after first launch. Native TextKit-2 Page editor **LIVE on `origin/main` at `9a0b383`, tagged `v0.2.7.0`**. 197/197 tests pass; build green; lint exit 0; engine builds standalone. (Prior "198" doc refs were off-by-one — current XCTest count verified by spot-check.)

**The pivot that mattered:** Phase A-G shipped on the Pallepadehat WKWebView fork (`Natertot215/PageEditorMD`). Phase G's smoke test failed Nathan's visual baseline despite Apple-typography work + transparent-bg defensive layers. Two pivots: brief Milkdown + Crepe candidate (also WKWebView), then a demo of `nodes-app/swift-markdown-engine`'s native TextKit-2 editor sealed it. Session 9 stripped the fork, vendored the engine, wired Pommora's editable title + body-binding chain, added UX polish passes driven by Nathan's first-look feedback. **Nathan: stoked and surprised at how good it looks.**

**Commits (all on `main`):**
- `1c6e270` v0.2.7-h.0 — docs repair reconciling Session-8 engine-swap decision (Handoff/Framework/History/CLAUDE/Planning)
- `3d23f52` v0.2.7-h.1 — Pallepadehat fork stripped (6 pbxproj entries + Package.resolved pin + `network.client` entitlement + External/PageEditorMD/ clone removed); body editor replaced with Phase-4 placeholder Text
- `ad2b879` v0.2.7-h.2 — swift-markdown-engine vendored as local Swift Package at `External/MarkdownEngine/` (Apache 2.0, 46 .swift files); Apple swift-markdown 0.8.0 exact added as Pommora SPM dep; minimal Swift-6 patches to engine sources (`@MainActor` on MarkdownInputHandler / MarkdownLists / MarkdownStyler / TextStylingService structs + MarkdownTextLayoutFragment overrides as `nonisolated` with `MainActor.assumeIsolated` bodies + selector-based notification observers in NativeTextViewCoordinator)
- `4fafed0` v0.2.7-h.3 — PageEditorView body swapped to `NativeTextViewWrapper(text: $viewModel.body, configuration: .default, fontName: "SF Pro Text", fontSize: 15, documentId: viewModel.page.id)`; editable title TextField preserved exactly; Apple swift-markdown 0.8.0 also added as engine-side dep (groundwork for deferred Phase 3)
- `b7a2535` v0.2.7-h.4 — character-pair auto-pair (`**`/`__`/`[[`/`` `` ``) added to engine's `MarkdownInputHandler.handleCharacterPairAutoPair(...)`; wired into NSTextViewDelegate's `shouldChangeTextIn` chain after image-embed auto-wrap, before list insertion; suppressed inside code blocks + when next char is close marker
- `9756f68` v0.2.7-h.5 — initial Session-9 doc ship-out across Handoff/Framework/History/CLAUDE reflecting v0.2.7 LIVE state
- `9b97393` v0.2.7-h.6 — doc self-correction: commit count + main SHA references in the h.5 doc tables (h.5 itself shifted main, its own SHA wasn't in the table it authored)
- `9e13c95` v0.2.7-h.7 — UX fixes batch: title-body padding 4 → 20pt; body editor `textInsets(horizontal: 24)` so body aligns under title; **auto-unpair on backspace** (`*|*` / `**|**` / `[[|]]` / `` `|` `` backspace deletes both halves, single undo step)
- `54d1ddd` v0.2.7-h.8 — **Apple-AST supplemental styler**: walks `Document(parsing:)` AST for BlockQuote/Strikethrough/Table/ThematicBreak (the GFM block types the engine's regex tokenizer doesn't cover). Composes additively on top of primary `MarkdownStyler`. Plus **expanded right-click menu**: Format (Bold/Italic/Strikethrough/Inline Code/Link) + Heading (H1-H6) + Lists (Bullet/Numbered) + new Block submenu (Blockquote/Code Block/Table/Horizontal Rule). 9 new `@objc` insert handlers
- `6719e11` v0.2.7-h.9 — **HR-as-real-line**: `---` renders as a 1pt full-width horizontal line via custom `MarkdownTextLayoutFragment.drawThematicBreak`. Dashes hidden via font-0.1 + clear foreground; range tagged with new `.pommoraThematicBreak` attribute. **Table source markup hidden**: all `|` pipes + the `|---|---|` separator row invisible (cell content stays styled). **Enter on title → body focus**: `focusBodyEditor()` walks `NSApp.keyWindow.contentView` for first NSTextView and makes it firstResponder
- `9a0b383` v0.2.7-h.10 — **HR draw-detection fixed**: `drawThematicBreak` now scans the whole fragment range via `enumerateAttribute` instead of only checking the first char (root cause: fragment range often starts at leading newline that doesn't carry the attribute). **Title focus via `@FocusState`**: `titleFocused = false` on submit before `focusBodyEditor()` so TextField cleanly relinquishes focus (was: stayed focused + auto-selected). **H5/H6 removed** from Heading submenu (render smaller than body text at Pommora's typical scales)

**Plan deviations from `// Planning//v0.2.7-engine-swap.md`:**

1. **Engine location** — plan said `Pommora/Pommora/PageEditor/Engine/` (raw vendoring); shipped at `External/MarkdownEngine/` (local Swift Package). Pommora's Swift 6 strict-concurrency + ExistentialAny clashed with engine's Swift 5.9 idioms — package boundary isolates the concurrency contract, avoiding cascading `@MainActor` across 46 files. Engine fully editable (we own External/ copy).

2. **Phase 3 deferred to v0.2.7.1** — plan's `MarkdownTokenizer.parseTokens(in:)` body swap to walk `Document(parsing: text)` AST + emit `[MarkdownToken]` shims (+ surgery on `MarkdownStyler.styleAttributes` + delete `MarkdownTokenizer+Emphasis.swift` and 6 `MarkdownStyler+*` extensions) deferred. Pommora-side files (`PommoraMarkdownStyler` / `PommoraInlineScanner` / `SourceRangeToNSRange` / `MarkersShrinker`) at `Pommora/Pommora/PageEditor/Styler/` morph into in-engine rewrites at v0.2.7.1. Apple swift-markdown 0.8.0 already wired in `External/MarkdownEngine/Package.swift` as groundwork. Engine ships v0.2.7 with existing regex-based tokenizer + styler — table / blockquote / strikethrough / ThematicBreak arrive with Phase 3.

3. **Phase 4.5 trimmed** — basic character-pair auto-pair ships (insertion only). Selection-wrap (`*` on selected text → `*text*`) + auto-exit-on-whitespace defer to v0.2.7.1. 11-test auto-pair suite also defers.

**Session-9 close & v0.2.7.0 release:**
- Tagged `main@9a0b383` as `v0.2.7.0`; pushed `main` + tag to `origin/main`. First origin push since v0.2.0 series; CI runner `runs-on: macos-26` resolution is the open question.
- Roadmap reorder: NavDropdown (was v0.2.8) → v0.2.7.2; Tables custom = v0.2.7.3; Sidebar reordering + drag = v0.2.7.4 (new). `NavDropdown.md` + `PommoraPRD.md` still reference NavDropdown as v0.2.8 — Nathan's other session reconciles.
- Live-feedback iteration loop took ~5 commits (h.7 → h.10) — highest-value part of the session. Pattern worth preserving for polish phases.

**What's still broken (v0.2.7.1 scope):**
- **Blockquote (`>`)** — current rendering is dimmed-text + bg tint + 20pt indent (h.8 supplemental styler). Apple-Notes-style needs vertical accent bar on leading edge + heavier bg shading. Replicable via `MarkdownTextLayoutFragment.draw` pattern — add `drawBlockquote(at:in:)` analogous to `drawCodeBlockBackground`; tag ranges with `.pommoraBlockquote: true`. Small lift.
- **HR (`---`)** — three fixes: auto-transform lock on typing (further `-` after `---` shouldn't extend); inset visual width by `textInsets.horizontal`; color confirm. Same pattern as existing draw hook.

Both replicable from Apple Notes / TextEdit native behaviors — not research-grade. Scoped to v0.2.7.1.

**Time-cost driver of deviations:** Swift 6 strict-concurrency cascades on vendored engine source. ~30% of session diagnosing `MarkdownTextLayoutFragment` NSTextLayoutFragment-override isolation mismatches + `NativeTextViewCoordinator` notification-observer Sendable failures before pivoting to local-SPM Swift-5.9-package strategy. Pivot resolved the cascade — engine needed only ~5 minimal `@MainActor` annotations on Input/Styling struct types to build clean.

**Architectural assurances intact:** Files-are-canonical (editor writes `.md` via `viewModel.body` → 300ms debounced save → `ContentManager.updatePage` → `PageFile.save` → `AtomicYAMLMarkdown.write` atomic temp+rename); frontmatter preservation (editor binds only to body, YAML stripped by `AtomicYAMLMarkdown.load`, re-serialized on save from typed `viewModel.page.frontmatter`); page-switch flush via PageEditorHost `.task(id:)` await `old.close()`; window-close / app-quit flush via AppGlobals lifecycle observers; editable title TextField at `PageEditorView.swift:53-63` preserved per plan; all 197 tests pass (none touched MarkdownEditor types — domain is editor-library-agnostic).

**Carried to v0.2.7.1:** Phase 3 substantive (AST tokenizer/styler rewrite); Phase 4.5 polish (selection-wrap + auto-exit + 11-test suite); Phase 6 (split `.claude/Features/Pages.md` editor-UX content into `Features/PageEditor.md`); `PommoraWikiLinkResolver` conformance to engine's `WikiLinkResolver` (v0.2.10 wikilink autocomplete + rename cascade); engine actor-isolation warning at `NativeTextViewWrapper.swift:213` (fix in same Phase 3 pass).

#### Session 7 — 2026-05-18 (second long session) — v0.2.7 Phase A-G ship + Milkdown pivot

Sprawling session: SPM dep on Pallepadehat fork → full domain layer + 10 tests → editor wires end-to-end → 5 polish iterations post-smoke → 2 fork-side polish iterations (Phase G #1 + #2) → Nathan-driven decision to swap to Milkdown + Crepe.

**Commits on `main` (8, none pushed):**
- `1df93a6` v0.2.7-a — SPM dep on `Natertot215/PageEditorMD` (Pallepadehat fork, branch=main)
- `ca33210` v0.2.7-b — Domain layer (PageRef + updatePage + PageEditorViewModel + 10 tests) + icon migration
- `74d1ea9` v0.2.7-c1 — Pommora.entitlements + CODE_SIGN_ENTITLEMENTS (4 keys: app-sandbox / user-selected.read-write / bookmarks.app-scope / network.client)
- `14e1c8a` v0.2.7-c2 — AppGlobals (weak VM registry + lifecycle flush observer) + AppState.pageInspectorOpen + PommoraApp.init bootstrap
- `62f4b7b` v0.2.7-c3 — Editor end-to-end: FrontmatterInspector + PageEditorView + PageEditorHost (`.task(id:)` page-switch flush) + sidebar wire
- `599ee2f` v0.2.7-c4 — Inspector dedupe + title banner (read-only)
- `454d153` v0.2.7-c5 — Editable title (TextField → renamePage → file rename) + inspector at NavigationSplitView level
- `dcb1ab0` v0.2.7-c5.1 — Inspector toggle INSIDE `.inspector(...)` closure (fixes left-side placement)
- `6882ea9` v0.2.7-c5.2 — Sidebar page-switching regression fix (`@State var viewModel` → `@Bindable` + `.id(vm.page.id)`)
- `2226fbe` v0.2.7-g — Package.resolved bump to fork `4fd91d6` (Phase G #1)
- `1989fac` v0.2.7-g.2 — Package.resolved bump to fork `addaa23` + SwiftUI `.background(Color.clear)` defensive layer

**Fork commits at `Natertot215/PageEditorMD` (all pushed):**
- `4fd91d6` — Phase G #1: drop active-line highlighting + Notes-style fold chevron + markdown-autopair.ts + tighter heading→body spacing + Apple typography overhaul (SF Pro Text body, SF Pro Display headings, SF Mono code, 28/22/17/15/13/13pt scale) + transparent bg CSS
- `a146a28` — Swift WKWebView triple-clear (drawsBackground KVC + underPageBackgroundColor + NSView layer bg)
- `addaa23` — `!important` on transparent bg rules to win over xcode theme

**Tests:** 186/186 → 198/198 (+12 in Phase B). Lint + build green throughout.

**Smoke-test + Milkdown decision:** Nathan smoke-tested Phase G post-clean-build; visual baseline still didn't ship Notion-like polish. Context7 research on Milkdown + Crepe: `@milkdown/crepe` is the polished out-of-box wrapper with `frame` / `crepe` / `nord` themes; `remark-directive` handles `:::callout` natively; custom inline nodes follow standardized 5-component pattern. Round-trip risk = body stylistic normalization (list marker / fence / heading style), accepted for primary single-source-of-truth use case.

**Locked decisions for the swap (Session 8 implements):**
- **Vendor wrapper as source inside Pommora's tree** (`Pommora/Pommora/PageEditor/` + `web/`), NOT SPM dep, NOT fork. Nathan needs to see every line.
- **Crepe's `frame` theme (most macOS-native) as default**. Pommora-brand styling layer comes AFTER baseline ships.
- **Defer Pommora extensions:** `:::callout` + `@Columns` → v0.2.9 (remark-directive). `[[wikilinks]]` → v0.2.10 (5-component plugin).
- **Stay WYSIWYG / Live Preview editing** (Crepe defaults).

**Survives swap:** PageRef, PageFile, PageMeta, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, Pommora.entitlements, all 198 tests, title-banner VStack + `.inspector` pattern.

**Stripped:** 6 pbxproj SPM entries for `MarkdownEditor`, Package.resolved entry for PageEditorMD, `import MarkdownEditor`, `pommoraEditorConfig`, Pallepadehat-specific `EditorWebView(...)`. The fork at `Natertot215/PageEditorMD` stays in git history as a parked branch.

**Sub-plan:** `.claude/Planning/v0.2.7-milkdown-swap.md` with three research areas (Strip / Setup / Construct styling) + verbatim resume prompt.

**Effort:** ~2.5-3 sessions to ship feature-equivalent + better UI baseline.

**Quirk added this session:** branch-pinned SPM forks don't bump via gentle `xcodebuild -resolvePackageDependencies` — need full nuke of `Package.resolved` + `DerivedData/.../SourcePackages` + `~/Library/Caches/org.swift.swiftpm/repositories/<DepName>-*`. Documented in `v0.2.7-g` commit message.

#### Decisions

##### Stack — SwiftUI

Stack is SwiftUI. Dual-stack evaluation (React+Electron vs SwiftUI) closed on SwiftUI for Mac cohesion, Apple ecosystem alignment, and iOS/iPad intent. React+Electron preserved as contingency at `// ReactInfo//`.

- **Editor strategy: two SwiftUI options.** Option 1 — native: NSTextView via `NSViewRepresentable` + `swift-markdown` + TextKit 2 (Clearly available as fork-reference, FSL-1.1-MIT → MIT Feb 2028). Option 2 (likely direction) — WKWebView hosting Tiptap / Milkdown / BlockNote / MarkdownEditor. Detail → `// Features//Pages.md`.
- **Mac OS integration first-party** on SwiftUI — QuickLook, CoreSpotlight, Share Extensions, Finder file-promise drag-out, sidebar vibrancy, accessibility. Detail → `PommoraPRD.md`.
- **Distribution** Sparkle 2.x for non-MAS auto-update; TestFlight for Mac; security-scoped bookmarks for MAS sandbox. Detail → `PommoraPRD.md`.
- **React-side editor research** at `// ReactInfo//Editor.md` — BlockNote (MPL-2.0) and Tiptap (MIT) co-primary; `@tiptap/markdown` first-party round-trip. Same candidates serve as Option 2 in-WebView editor on Swift.

##### SwiftUI research findings (preserved)

- `TextEditor(text: Binding<AttributedString>, selection:)` documented for iOS 26+ / macOS 26+ (Tahoe).
- `apple/swift-markdown` suitable as parse / AST / query layer. `MarkupFormatter` reformats rather than round-trips; not a fit for save path — hand-rolled writer expected.
- Native `.draggable` + `.dropDestination` + `Transferable` are Apple's documented D&D API for new SwiftUI code.
- Wikilinks-as-styled-spans follows WWDC25 Session 280 rich-text guidance; verified in build.
- `AttributedString(markdown:)` is one-way (no `.markdown` accessor) — save path needs its own writer.
- swift-markdown block directives use DocC `@Name(args){...}` syntax (NOT Pandoc / Obsidian `:::`), via `ParseOptions.parseBlockDirectives`. A `:::` ↔ `@` preprocessor or swift-markdown fork needed for Pommora directives.
- Candidate component libraries: `stevengharris/SplitView`, `visfitness/reorderable`, `SwiftUIX/SwiftUIX`. Selection at build time.
- References: WWDC25 Session 280 ("Cook up a rich text experience in SwiftUI with AttributedString"); Apple "Building rich SwiftUI text experiences".

##### Architecture (three load-bearing constraints)
1. **Stack portability of functionalities** — file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design values, UX patterns survive a stack rebuild. Codebase doesn't. **No enforced layer separation** (Core/Adapter/UI rule dropped); portability comes from documented decisions.
2. **Cross-nexus queryability + cloud sync compatibility** — Collections aren't isolated; queryable and linkable from anywhere. On-disk model maps cleanly to a cloud DB (shared `pages` / `items` tables keyed by `collection_id`; `_collection.json` → `collections` row; each Space → `spaces` row). Sync arrives as additive translation. Cloud sync is real long-term intent.
3. **Persistent immediate legibility for agents** — every entity is a file an external agent reads directly without tool-call round-trips. SQLite is performance scaffolding, not source of truth. Differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (legible but unstructured). Pommora = local + structured.

##### Domain Model (revised 2026-05-16 — replaces earlier 3-entity model)

**2-layer PARA-aligned model:**
- **Organization layer — Contexts** (3 tiers): **Spaces** (1, broad life domains) / **Topics** (2, subject areas) / **Sub-topics** (3, specifics within a Topic). All three are composed-blocks surfaces.
- **Operational layer — Vaults + Agenda:** **Vaults** (folder + `_vault.json` with shared schema) contain **Collections** (sub-folders sharing the Vault's schema in v1) which contain **Pages** (`.md`) + **Items** (`.json`). **Agenda** is a sibling of Vaults at `<nexus>/Agenda/` holding `.agenda.json` files with EventKit integration.
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.

**Tier system rules:**
- Tier-parent rule — every `parents[i]` resolves to a Context with `level < this.tier`. Cycles impossible by construction.
- Topics multi-parent across Spaces; Sub-topics single-parent at file (folder location = parent Topic) with additional `linked_relations` as typed multi-valued relation property.
- No same-tier file-structural links (Topic ↛ Topic; Space ↛ Space).
- Tier-skip allowed.
- Per-tier labels user-configurable per-Nexus (Capacities-style singular + plural in `.nexus/tier-config.json`).
- **Three tiers default; tier 3 ("Sub-topics") exposed in v1.** Code/schema supports a fourth tier without changes (gated by `exposed` flag).

**Operational layer rules:**
- Vaults are **kind-agnostic** — Pages and Items coexist under the shared Vault schema. Earlier `kind: "pages" | "items"` Collection typing is gone.
- Collections in v1 are pure sub-folders (no own metadata file, no own schema). Collection-local schema overrides are a post-v1 Prospect.
- **Tasks and calendar events are NOT Items** — they live as **Agenda items** with EventKit integration. Schema is unified (no `kind` discriminator); user-facing type (Task / To-Do / Phase / Event / custom) is a `properties.type` Select.
- Per-tier multi-relations (`tier1` / `tier2` / `tier3`) on Items / Pages / Agenda items replace the earlier `spaces` multi-relation.
- Move-strip rule survives — moving Content between Vaults strips properties not in destination schema with confirm.
- No in-place Item ↔ Page promotion in v1 (Prospect).
- No default seeded Collections; first launch seeds the singleton Homepage entity (not a Space).

**Sidebar shape:**
- Four top-level sections: **Saved / Spaces / Topics / Vaults**. Replaces the earlier three-heading model (Spaces / Saved / Collections).
- Saved holds three fixed entries (Homepage / Calendar / Recents) with renamable labels (`saved-config.json`).
- Agenda items don't appear in the sidebar — accessed via Saved → Calendar.

**Inline editing principle (locked):**
- Every embedded view in a composed-blocks surface (Context, Homepage) is a live, fully-editable view of its source — never a read-only snapshot.
- Edits route through source entity's manager → atomic write → file watcher → SQLite re-index → all embedded views refresh.
- Full inline editing of a referenced Page's body (Notion "synced blocks") is post-v1 (Prospect).

**EventKit integration contract:**
- Agenda items map to `EKEvent` / `EKReminder` based on which time fields are populated.
- Sandbox entitlement `com.apple.security.personal-information.calendars` + Info.plist usage description keys + modern `requestFullAccessTo*` APIs required.
- Sync NOT enabled by default in v1 — opt-in via Settings.

**Full revised spec** lives at `// Planning//Contexts-Vaults-spec.md` (file schemas, validation, CRUD scope, 11-phase implementation plan, SwiftUI research findings, day-1 working plan, doc-rewrite tracking).

##### Storage Layout
- **Nexus location is user-pickable on first launch** (default suggestion `~// PommoraNexus//`). The user can place the nexus in iCloud Drive / Dropbox / any synced folder for free device-to-device sync in v1.
- **App-internal config folder: `.nexus//`** (leading dot, hidden by default — matches `.obsidian` convention; renamed from the earlier underscore-prefix `_pommora//`). Lives inside the nexus. v0.1a holds `nexus.json` (vault-portable identity: ULID + createdAt). v0.2+ adds `state.json` (vault-portable user state: open tabs, sidebar collapsed state) and `spaces//` (`.space.json` files).
- **`nexus.db` lives outside the nexus** at `~//Library//Application Support//com.nathantaichman.Pommora//nexuses//<nexus-id>//nexus.db`. Resolves the iCloud-sync corruption risk that motivated moving SQLite out of the cloud-syncable nexus folder. Per-nexus subdir keyed by ULID survives nexus rename/move; marked `isExcludedFromBackupKey` so iCloud Backup skips the regeneratable index. Per Apple Foundation + GRDB.swift recommendation; SQLite official guidance against placing DBs on network filesystems.
- **App-level state.json** at `~//Library//Application Support//com.nathantaichman.Pommora//state.json` holds machine-specific state (security-scoped bookmark of the last-opened nexus; future recent-nexuses, last-window-frame). No UserDefaults dependency.
- **Three Codable files, three concerns:** identity (`<nexus>/.nexus/nexus.json`, vault-portable, ULID-based), app state (`App Support/.../state.json`, machine-specific, holds bookmarks), nexus user state (`<nexus>/.nexus/state.json`, vault-portable, future v0.2+). The boundary is enforced by *where the file physically lives*, not by code.
- **Nexus-local trash: `.trash//`** at the nexus root (sibling of `.nexus//`). Deleted entities move here, preserving original relative path. Restoration is a straight file move back. Auto-purge / age-based clearing is post-v1; v1 ships with manual clear only.
- **`.space.json` files** carry the full block tree. `_collection.json` is the Collection's schema sidecar (Make.md folder-notes pattern).
- **Files canonical, SQLite as index.** Markdown for Pages; JSON for everything else. SQLite is regeneratable from files.
- **Cloud-sync mapping** in PRD: a single shared `pages` table with `collection_id` + `properties` JSONB column; parallel `items` table with the same shape; one `collections` row per `_collection.json`; one `spaces` row per `.space.json`.

##### Property Model
- **No free-form text property.** Title is the filename; "text-shaped" values use Select / Multi-select with creatable options (Notion behavior).
- **No dedicated `Status` type.** Status-like behavior = a Select named "Status" with user-defined options.
- **v1 catalog (8 types):** number, checkbox, date, datetime, select, multi-select, relation, URL.
- **Per-Collection schemas** — each `_collection.json` holds its own property schema and saved views. No shared schemas file.
- **Property values** — Pages in YAML frontmatter; Items in the `.json` file's `properties` key. Same catalog, two storage substrates.
- **Color palette for Select / Multi-select** = fixed 9-color Notion palette (`gray`, `brown`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `red`). Custom hex picker is a Prospect.
- **Property panel shows every schema property always** (Notion-style), even unset. Hide-empty is a Prospect.
- **Option order within Select / Multi-select properties defines sort behavior** — drag-to-reorder options; ascending sort returns first-listed first. Replaces alphabetical sort.
- **View-level column ordering is visual, per-view** (drag column headers; stored in the view spec). Schema-level property declaration order is append-on-add in v1.
- **Inline cell editing in Table view** confirmed.
- **Relations are stored by ID** (rename-safe) and **displayed as the target's current title** (resolves ID → title at render time; renames update display automatically).
- **Move-strip rule (Notion-style):** moving a member across Collections (or in/out of loose state) strips properties not in the destination schema. No `_orphaned` quarantine, no backup. **User gets a simple confirmation warning** listing which properties will be stripped before the move proceeds. Same rule applies to property deletion.
- **Auto-managed fields**: `id` (ULID), `created_at`, `modified_at` on every member and every loose entity.

##### Editor
- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips/pills.
- **Pages are Markdown documents, not block surfaces** — one continuous Markdown stream. "Block-level features" as a project term belongs to Spaces only.
- **Two Pommora-specific Markdown directives on Pages**: `@Columns` (`:::columns`) renders a section in N horizontal columns; `:::callout` renders an outlined-box callout (distinct from blockquotes). Both directives resolve cleanly when read by external Markdown tools.
- **Standard Markdown features**: paragraphs, headings H1–H5 (in v0's type scale; no H6 token; **headings are foldable by default** — built-in UI, not a directive), lists, code blocks + inline code, images, GFM tables, blockquotes, horizontal rules. Tables are GFM. Dividers are `---`. Side-by-side callouts or blockquotes via `@Columns` wrapping.
- **Blockquotes vs callouts are distinct constructs.** Blockquotes use standard `>` syntax and render as a filled box with a left-side emphasis bar. Callouts use the `:::callout` directive and render as a minimally-rounded outlined box. Each binds to its own brand-value family — `blockquote// fg` / `bg` / `accent` (left bar) and `callout// fg` / `bg` / `border` — alongside SwiftUI semantic colors.
- **Code rendering.** Code blocks and inline code render in SF Mono at 1.0 em. Foreground and background bind to Pommora-brand values (`code// fg`, `code// bg`) so the code palette can be tuned independently of text and accent.
- **Columns are equidistant in v1** — width division by child count. Adjustable widths deferred.
- **`@View` (in-line database view embed in a Page) is deferred to v2+.** Easier on Option 2 (WKWebView + JS editor — same node-component approach BlockNote and Tiptap support directly); harder on Option 1 (native editor) due to layout-attachment complexity. Embedded Collection views remain available *inside Spaces* (widget blocks) for v1.
- **Wikilink syntax variants in scope, incremental**: `[[Page Name]]` ships in v0.5; aliases (`[[name|alias]]`), heading anchors (`[[name#heading]]`), and asset embeds (`![[asset]]`) land as follow-ups.
- **Editor serialization architecture (load-bearing, applies to either option):** (a) Canonical on-disk = Markdown for Pages, JSON for Spaces / Items / Collections. (b) Rich in-editor working format = styled attributes on Option 1, JS editor's block tree on Option 2. (c) Explicit serializers bridge the two for Pommora directives (`:::columns`, `:::callout`, wikilinks). Stack-agnostic principle in `// Features//Architecture.md`; React-side detail (BlockNote `blocksToMarkdownLossy` / `tryParseMarkdownToBlocks`, Tiptap `editor.getJSON()` + `@tiptap/markdown`) at `// ReactInfo//Editor.md`.
- **SwiftUI editor options.** Option 1 (native): NSTextView via `NSViewRepresentable` + `swift-markdown` + TextKit 2 — text storage IS the Markdown source, styling layered as attributes, marker hiding/reveal selection-driven. Clearly is fork-able baseline. Option 2 (likely): WKWebView hosting Tiptap / Milkdown / BlockNote / MarkdownEditor. [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) is the production reference; [Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor) is a Swift Package wrapping CodeMirror 6 in WKWebView with Obsidian-style syntax hiding, GFM tables, SF fonts (MIT; single contributor — fork rather than depend). Pommora extensions to add: `:::callout`, `:::columns`, wikilinks (CM6 extensions). `file://` ES-module block resolved by `WKURLSchemeHandler` registered for custom scheme (Apple-documented); cross-origin caveat doesn't bite when bundle ships inside `.app`.

##### Sidebar + Shell
- **Three top-level collapsible headings, default-collapsed, user-reorderable**: Spaces (leaf labels), Saved (non-operational placeholder in v1 — pinning is post-v1), Collections (kind-agnostic; each Collection is a folder-style disclosure).
- **Sidebar selection language locked**: custom `SelectableRow` with tap-driven `@State var selection: String?` (not `List(selection:)`). `Color.gray.opacity(0.11)` rounded fill via `.listRowBackground`, accent foreground on selected icon + text, `+0.11` brightness via `.brightness(_:)` to compensate for fill dimming, `.symbolRenderingMode(.monochrome)`. Required because `.tint(_:)` doesn't recolor sidebar List selection on macOS Tahoe — NSTableView ignores SwiftUI's tint for `.sourceList` highlight. Custom approach also combines gray fill + accent foreground. Trade-off: fill doesn't desaturate on window unfocus like Finder/Mail. Detail → `// Features//Sidebar.md`.
- **No Loose sidebar group.** Loose entities reach via search, wikilinks, or pinning.
- **No raw filesystem view in v1.**
- **"Collapsed-by-default disclosure"** is the general UI pattern for any hierarchical or grouped content.
- **Three-pane shell** (240 sidebar / flex main / 280 inspector, hidden by default in v0.0): two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)` at split-view level. Two-column chosen because third column is for drill-down, not contextual side panel. System sidebar toggle (NSSplitView animation, Mail/Notes/Finder pattern); inspector toggle inside `.inspector { … }` closure (anchors to inspector toolbar segment), wrapped in `withAnimation(.smooth(duration: 0.30))`. Widths persist. Property-panel content lands v0.6.
- **Main pane is multi-tabbed** (Obsidian / Notion pattern). Tab row at top; each tab = one open view (Page / Collection with active view / Space). **Tab chrome + navigation ship v0.1** when files open (v0.0 has no tab chrome — chrome-without-functionality removed as dead weight). `+` / `×` / `Cmd+T` / `Cmd+W` / `Cmd+1..9` / `Ctrl+Tab` shortcuts. Open tabs + active tab persist. Items don't get tabs in v1 — they open in **Item window**: popover-style floating surface anchored to trigger (Calendar-event-detail pattern), holding title + property inputs + 250-char description. Tabs reserved for full-pane views; inspector is Page property panels only. Detail → `PommoraPRD.md`.
- **Property panel default location is the right inspector pane.** Below-heading and page-bottom placements are Prospects.
- **Inspector pane has two planned views.** Default view in v1 is the property panel for the active Page. An **AI chat interface** is a planned future addition (post-v1) — a frontend to Nathan's existing local CLI (not an API integration; the same pattern he already uses on Obsidian). See `// Features//Prospects.md`.

##### Views
- **Five view types in v1**: table, board, list, cards, gallery.
- **Inline cell editing** in Table view; **board view ships as visual kanban layout** in v0.9 (cards grouped by a property's options; edit a card to "move" it); **drag-to-rewrite-frontmatter kanban** is a planned post-v1.0 follow-up.
- **Two contexts for views**: inside a Collection (saved views in `_collection.json`); embedded as a Space widget (filter / sort / group / shown-properties override locally).

##### Scope and Posture
- **Mac for v1**; Linux / Windows aren't on the v1 path and become contingency-only on SwiftUI. **iOS / iPad is real long-term intent** — SwiftUI ships there essentially for free; one of the values that drove the SwiftUI lock.
- **Plugin system out of scope**, now and indefinitely. Personal tool, not a platform.
- **Versioning / file history delegated to OS tools** (Time Machine, git, filesystem snapshots). Pommora handles in-session undo only.
- **Single-user.** Multi-user collaboration is out of scope.

##### First-Launch Experience
- **Empty sidebars + seeded `Homepage` Space.** No tutorial, no walkthrough wizard. First Pages / Collections are user-created.

##### Design System
- **Swift-native baseline.** SwiftUI semantic colors + Pommora-brand `Color` / `Font` extensions for values not covered by native semantics; component library at `// UI-UX//Components//` consumes them. For Swift, only a small subset matters (accent, code, callout, blockquote); semantic colors carry the rest. Full ~118-token Figma-built taxonomy is React-flavored, preserved at `// ReactInfo//Styling-Tokens.md`.
- **One initial scheme** in v0.x — no built-in light / dark; in-app customization is limited to accent color + font size (Framework v0.12). SwiftUI semantic colors, Materials, and Dynamic Type cover the rest natively.
- **Visual direction:** Notion-comfortable density; pastel-leaning color treatment (muted / desaturated); flat dark chrome (no shadows except on overlays); mixed-scale rounding (pill for tags / chips, tight for buttons / toggles / labels, surface for cards / panels / modals — Notion / Claude-style).
- **Typography pairing:** SF Pro (sans) + SF Mono (mono), system-native via SwiftUI Font scale. Heading scale is em-relative (H1–H5; no H6 in v0) so changing body rescales every heading.
- **Accent:** Single-hue, 2×2 matrix — primary/active, primary/muted, secondary/active, secondary/muted. All 4 stops share the same hue; descending in saturation + lightness. App accent color lives in `Assets.xcassets/AccentColor.colorset`; the other stops live as `Color+Pommora.swift` extensions. Specific hue is deferred — Xcode default stands in until the design lock.
- **SF Symbols on Swift** via `Image(systemName:)` — no indirection layer. (Material Symbols + role-indirection via `.nexus//symbols.json` is the React-side approach, preserved at `// ReactInfo//Symbols-guide.md`.)
- **In-app customization** (Framework v0.12) covers two values: accent color and font size. SwiftUI handles dark mode, semantic colors, Materials, and Dynamic Type natively — no additional override surface needed. Spacing / radius / shadow stay on baseline.
- **Disclosure pattern + DisclosureLine.** Multiple disclosure types (tree/folder, heading, toggle block, sidebar section header), all built on one `Disclosure` primitive with `indent line` variant. `true` for tree/folder — renders `DisclosureLine` hairline guide tracing depth (Obsidian / VSCode). `false` for heading + toggle blocks — no line. DisclosureLine is a sub-element of Disclosure, never independent.

#### Features Implemented

**v0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`. Sidebar (240 default, drag-resizable) + main pane (`EmptyPane` — `windowBackgroundColor` fill) + pop-out inspector (280 default, hidden by default). Inspector toggle: `sidebar.trailing` SF Symbol at `.primaryAction` inside the `.inspector { … }` closure, wrapped in `withAnimation(.smooth(duration: 0.30))`. Sidebar collapse via system `≡` (`NSSplitView` native animation). View menu's "Show Inspector" via `InspectorCommands()`. Window 1440×810 default, 960×560 min. Title suppressed via `.windowToolbarStyle(.unified(showsTitle: false))`. `NSSearchField` via `NSViewRepresentable`, anchored to `.safeAreaInset(.top, spacing: 8)` — preserved into v0.1a. The placeholder sidebar Sections shipped in v0.0 were replaced by real folder content in v0.1a.

**v0.1a — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, hidden `.nexus/` folder init, sidebar mirroring user-picked nexus folder.

- **Sandbox** via `ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readwrite` (Xcode 15+ auto-generates entitlements plist; no separate `.entitlements` file). Verified via `codesign -d --entitlements -`.
- **Code structure:** single app target; `Nexus/` and `Sidebar/` auto-included by Xcode 16's `PBXFileSystemSynchronizedRootGroup`. Files: [`Nexus`](Pommora/Pommora/Nexus/Nexus.swift), [`NexusManager`](Pommora/Pommora/Nexus/NexusManager.swift) (@Observable @MainActor), [`NexusBookmark`](Pommora/Pommora/Nexus/NexusBookmark.swift), [`NexusStore`](Pommora/Pommora/Nexus/NexusStore.swift), [`NexusIdentity`](Pommora/Pommora/Nexus/NexusIdentity.swift) (Codable `nexus.json`), [`AppState`](Pommora/Pommora/Nexus/AppState.swift) (Codable `state.json`), [`ULID`](Pommora/Pommora/Nexus/ULID.swift) (inline spec-compliant generator), [`FolderTree`](Pommora/Pommora/Nexus/FolderTree.swift), plus [`SidebarNode`](Pommora/Pommora/Sidebar/SidebarNode.swift), [`SidebarRow`](Pommora/Pommora/Sidebar/SidebarRow.swift), [`SidebarView`](Pommora/Pommora/Sidebar/SidebarView.swift) (`List` with recursive `OutlineGroup`).
- **Init flow:** existing `.nexus/` → load `nexus.json`. Empty folder → silent init. Non-empty → confirm dialog. `NSOpenPanel` defaults to `~/PommoraNexus/` if exists, else `~/`.
- **State separation:** machine-specific bookmark at `~/Library/Application Support/com.nathantaichman.Pommora/state.json`; vault-portable identity at `<nexus>/.nexus/nexus.json`; nexus-portable user state at `<nexus>/.nexus/state.json` (deferred to v0.2+).
- **Per-nexus DB path** reserved at `App Support/.../nexuses/<nexus-id>/nexus.db`; marked `isExcludedFromBackupKey = true`. DB created by GRDB in v0.2.
- **Menu commands:** File → Open Nexus… (⌘O); Debug → Reset Nexus Bookmark (DEBUG-only).
- **Tests:** 25 unit tests across `ULIDTests`, `AppStateTests`, `NexusIdentityTests`, `NexusStoreTests`, `FolderTreeTests`.
- **Stylistic UI copy intentionally absent** per direction — no welcome screens, error alerts, empty-state descriptions, NSOpenPanel customizations. Design pass adds these.

Design + 4 implementation Findings preserved at [.claude/Planning/v0.1-nexus-foundation-design.md](.claude/Planning/v0.1-nexus-foundation-design.md).

**Post-v0.1a sidebar visual scaffolding pass.** Sidebar UI swapped from FolderTree-driven to hardcoded placeholder Sections (3 loose Items + Spaces section × 3 entries + Collections section with 3 collection-folders × 3 placeholders each) to iterate on selection language without real-data noise. New private `SelectableRow` view consolidates icon + text + tap selection + selection chrome. `FolderTree` / `SidebarNode` / `SidebarRow` remain in the target but dormant — re-wire when de-scaffolding. `EmptyPane` removed from `ContentView`; detail closure is bare `Color.clear`. Inspector toggle stays in `.inspector { ... }.toolbar { }` per the v0.0 UIX-Guide direction (the toolbar-move experiment from commit 807057d was reverted in-session). Pommora-specific selection language captured in the Sidebar+Shell decisions above and documented at `// Features//Sidebar.md`.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 1 (2026-05-16).** Tasks 1-44 of 65 from `// Planning//Paradigm-Scaffolding-Tasks.md` shipped on a feature branch, plus 4 cleanup commits — 48 total. Data layer is feature-complete for v0.2: every entity in the locked paradigm (Space / Topic / Sub-topic / Vault / Collection / Item / Page / AgendaItem / AgendaSchema / Recurrence / Homepage / TierConfig / SavedConfig) has Codable, validator, and `@MainActor @Observable` manager. Swift 6 strict concurrency + ExistentialAny upcoming feature both enabled (flipped Task 1). Yams 5.4.0 added via SPM (Task 2). All custom Codable signatures use `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)` and all manager `pendingError` fields use `(any Error)?` per cleanup sweeps. UI tier (sidebar replacement + sheets + detail pane + Item Window + ContentView wiring) is Tasks 45-65, deferred to session 2.

Paradigm-solidifying decisions confirmed during session 1 (registry at `// Guidelines//Paradigm-Decisions.md`):
- **`PropertyValue.relation` encodes as tagged JSON object `{"$rel": "<ULID>"}`** — not bare string. Makes relation edges legible to external agents + graph-view indexer without consulting Vault schema; satisfies load-bearing constraint #3.
- **Collections persist a minimal `_collection.json` sidecar** with `{id, vault_id, modified_at}` — Collection is now Codable (no longer pure folder); parent-Vault relation is explicit on-disk property. Supersedes the original spec's "no metadata file" design.
- **SF Symbol picker = `xnth97/SymbolPicker` SPM dep, wrapped behind Pommora's `IconPickerSheet`** — wrapper isolates third-party API; swapping libraries is a single-file rewrite.

A new operating protocol installed in `// Guidelines//Paradigm-Decisions.md`: future paradigm-solidifying choices (on-disk schemas, wire encodings, defaults that lock once data exists, file-layout choices, cross-entity contracts, error semantics, identifier conventions) MUST surface via confirmation BEFORE the code lands, not after-the-fact.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 2 (2026-05-17).** Tasks 45-65 shipped (21 commits, **69 total ahead of `main`**). UI tier end-to-end: SidebarSheet + SidebarConfirmation enums; SidebarView four-section layout (Saved / Spaces / Topics / Vaults) with SelectionTag; 5 row views (SpaceRow / TopicRow / SubtopicRow / VaultRow / CollectionRow + ParentSpaceTags); 10 sheets (NewSpace / NewTopic / NewSubtopic / NewVault / NewCollection / NewPage / NewItem / EditTopicParents / SpaceColorPicker + ColorPickerSheet / IconPickerSheet wrapping SymbolPicker); detail-pane tier (ContentItem + DetailRow + ContextDetailPlaceholder / VaultDetailView + CollectionDetailView with native `Table(_:children:)` / SidebarDetailView dispatcher); ItemWindow tier (MultiSelectChips + FlowLayout / PropertyEditorRow / ItemWindow popover with title + icon + description + property editors + tier1/2/3 read-only); ContentView 8-manager wiring with real `contextProvider` closures via in-body snapshot-capture. **177 tests, 0 failures, 0 warnings, entitlements verified.** SymbolPicker 1.6.2 via SPM.

Code review at session end (CodeRabbit + synthesis) — 45 findings, ~10 real. Four-commit cleanup plan in `Handoff.md`: (1) dead-code purge (`SheetStubView` + v0.1a FolderTree trio); (2) sidebar UX restructure per right-click-context-menu direction + row commit() draft-loss fix; (3) Pages-under-Vaults/Collections sidebar disclosure; (4) atomicity + error-surfacing (6 rename sites, pendingError-on-CRUD, AgendaManager orphan fix, PageFrontmatter required-id, 8 validators trim consistency, ContentView initial-construction race, AtomicYAMLMarkdown force-unwrap, VaultDetailView modifiedAt, ItemWindow applyDraft helper).

Paradigm-solidifying decisions session 2 (appended to `// Guidelines//Paradigm-Decisions.md`):
- **Stub-and-progressively-replace execution strategy.** For branch-spanning plans with forward-dependencies, write each task with throwaway in-file stubs for not-yet-shipped types; later tasks replace stubs in-place. Every commit ships green standalone, independently verifiable. Supersedes spec's batch-commit-at-end (uncommitted 12-task blobs where any single break contaminates the batch).
- **Sidebar UX direction.** All "+ New" removed from sidebar; replaced by **right-click context menus location-scoped to the cursor** (right-click Vault row → "New Collection / New Page" bind to THAT Vault; right-click Collection row → "New Page" binds to THAT Collection). Saved Section keeps wrapper for future pinned items but loses literal "Saved" header — renders as heading-less group at top. **Pages appear in sidebar** under parent Vault (root) or Collection with `doc.text` icon (click no-op until v0.3 editor). **Items, Agenda items, Events do NOT appear in sidebar** — only detail-pane Tables. Hover-icon "+" on section headings skipped; quick-capture (Cmd+Shift+N / menu-bar) absorbs most CRUD entry before v1.

The React+Electron-locked v0.0 spec is preserved at `// ReactInfo// v0.0.md` for contingency.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 3 (2026-05-17/18) — cleanup + UX polish + Commit 4.** All 4 planned cleanup commits shipped + a longer-than-planned sidebar polish iteration sequence. **13 cleanup commits this session, branch landed at 82 commits ahead of `main`.** 182/182 unit tests pass, 0 source warnings, sandbox entitlements verified, app launches cleanly under test harness.

Commits shipped:

1. **`1343e50`** — Dead code purge: `SheetStubView` + v0.1a folder-tree trio (`FolderTree` / `SidebarNode` / `SidebarRow` / `FolderTreeTests`).
2. **`c8dbac6`** — Sidebar UX restructure: right-click context menus replace 5 "+ New" buttons; preserve rename drafts on error; new `SidebarSheet.newPageInVault(vault:)` case; section-area `Color.clear` hit-test rows (later replaced).
3. **`02da8ff`** — Pages-in-Vault-root + show Pages in sidebar under Vaults/Collections: `ContentManager` gained `pagesByVaultRoot` / `itemsByVaultRoot` storage + `pages(in vault:)` / `items(in vault:)` accessors + 4 `(inVaultRoot vault:)` CRUD overloads; new `PageRow` (non-selectable leaf, `doc.text` icon); new `PageParent` enum.
4. **`1a84a5f`** — Sidebar regressions fix: restore full-row click via `Spacer(minLength: 0)` + `.frame(maxWidth: .infinity)` + `.listRowInsets`; restore section disclosure chevrons via `Section(isExpanded:) { } header: { SectionHeader(...) }`; replace empty `Color.clear` hit-test rows with custom `SectionHeader` containing `+` button + context menu.
5. **`64e6cd8`** — Sidebar polish: hover-only `+` button via `.opacity(hovered ? 1 : 0).animation(.easeInOut(duration: 0.12))`; selection chrome on DisclosureGroup-wrapped rows via in-content `.background` (later reverted); `SelectableRow` becomes generic `SelectableRow<Trailing: View>` with trailing slot for TopicRow's `ParentSpaceTags`.
6. **`9971a35`** — Sidebar fixes batch: SF Symbol picker via new `IconPickerField` (wraps `SymbolPicker` directly, bypassing `IconPickerSheet`'s manager-routing) wired into all 4 Create sheets; `SpaceColor.accent` case added; renamingRow in all 6 row files keeps icon visible (only text editable); `.onChange(of: renameFocused)` with `isCommitting` guard auto-cancels rename on click-off without blocking Enter-commit.
7. **`2d707a0`** — Atomicity rollback + pendingError-based error surfacing + 8 small fixes + 4 Commit-3 reviewer carryovers: new `RenameAtomicityError`; rollback at 8 rename sites; all 8 managers wrap CRUD in `do/catch` setting `pendingError`; new `SidebarToast` view observes 5 managers' `pendingError`, renders dismissable banner above List; replaced silent `try?` calls in SidebarView delete handlers + IconPickerSheet + ColorPickerSheet + PageRow delete; `PageFrontmatter.id` required-decode; `AgendaManager.updateItem` refuses title changes (extracted `renameAgendaItem`); `VaultDetailView` uses `coll.modifiedAt`; `ContentView.onChange(initial: true)`; 8 validators trim consistency; `AtomicYAMLMarkdown` UTF-8 throws; `ItemWindow.applyDraft` helper; `ContentManager` split into `ContentManager.swift` + `ContentManager+CRUD.swift` (storage + load in main; 13 CRUD methods in extension); `existingInCollection:` → `existingSiblings:` rename; `@discardableResult` symmetry on Collection-scoped create methods; PageRow's `confirmingDelete` binding dropped; +5 new tests (`RenameAtomicityTests` + AgendaManager rename tests).
8. **`3657cad`** — Launch crash fix: `ContentView`'s sidebar branch missing `.environment(contentMgr)` injection. Commit 3 added `@Environment(ContentManager.self)` reads to VaultRow/CollectionRow/PageRow but parent never injected — Commit 2b's section restructuring shifted diff traversal timing enough to surface as `EXC_BREAKPOINT in EnvironmentValues.subscript.getter` via `OutlineListCoordinator.recursivelyDiffRows`. Bisected via parallel test runs at 3 SHAs. One-line fix.
9. **`838b063`** — Accent swatch polish: rainbow `AngularGradient` for `SpaceColor.accent` (matches macOS Finder Multicolor tag) + 5x2 fixed-column grid for the now-10 options.
10. **`8fe91d7`** — Detail-pane fixes: `SidebarDetailView` gained `.sheet(item: $presentedSheet)` so detail-pane "+ New Collection / New Page / New Item" buttons actually present sheets (Nathan's ContentView edit passed binding but no `.sheet` wired); `VaultDetailView` rows now include vault-root Pages + Items as top-level rows; `VaultDetailView.task` loads vault-root content; `SavedSection` dropped `header: { EmptyView() }` (was reserving height, creating top gap under search bar).
11. **`ae8280d`** — Restored `.listRowBackground` for sidebar selection chrome: removed `SelectableRow`'s in-content `.background`; added `SelectionChrome` view rendering `RoundedRectangle.fill(...).padding(EdgeInsets(top: 2, leading: 11, bottom: 2, trailing: 11))`; each row applies `.listRowBackground(SelectionChrome(isSelected: ...))` at body root. Attempted asymmetric `.disclosure` style (leading 0 to cover chevron); reverted to symmetric `.flat` (both 11pt).
12. **`576d933`** — Sidebar geometry consistency: HStack spacing 10 → 8 in SelectableRow + 6 renamingRow blocks; Image `.font(.system(size: 14, weight: .regular))`; `.frame(width: 16, height: 16, alignment: .center)` centers glyphs in fixed box so text always starts at same X; renamingRow geometry mirrors SelectableRow.
13. **`8cc492b`** — Symmetric chrome for disclosure rows: TopicRow / VaultRow / CollectionRow `SelectionChrome` switched from `.disclosure` (leading 0, trailing 11) to default `.flat` (11pt symmetric) so corners have matching radius. Trade-off: chevron may sit outside chrome's left edge in some widths; revisit via hand-rolled chevron if visually wrong.
14. **`0bc4c8d`** — Selection polish: Nathan-tweaked chrome opacity (0.11 → 0.10) and text brightness (0.12 → 0.10) for subtler selection.

Plus a parallel SpaceColorPicker tweak (made `color` binding optional + tap-toggle-deselect) shipped via Nathan's separate session — captured in the working-tree handoff state.

**Paradigm-solidifying decisions added during session 3** (appended to `// Guidelines//Paradigm-Decisions.md`):

- **Sidebar selection chrome via `.listRowBackground` at row file level.** Locked after the long polish iteration. `Color.gray.opacity(0.10)` fill, 6pt continuous corner radius, symmetric 11pt horizontal + 2pt vertical inset, text brightness 0.10, icon no brightness, HStack content spacing 8pt, icon column 16x16 centered at 14pt glyph size, row content padding 4pt leading / 0 trailing / 6pt vertical. Chrome applied at each row file's body root (DisclosureGroup itself for wrapped rows; row body for flat rows + Saved items per iteration) so it covers the chevron gutter. SelectableRow keeps no chrome — purely content. `SectionHeader` (private struct in SidebarView) renders a secondary-styled title + hover-only `+` button via `.opacity(hovered ? 1 : 0).allowsHitTesting(hovered).animation(.easeInOut(duration: 0.12))` (opacity not conditional rendering to avoid layout shift); right-click context menu surfaces "New X" regardless of hover.

- **Pages editor stack: Tiptap (ProseMirror) in WKWebView, MarkEdit-pattern native shell, vanilla TypeScript bundle.** Closes the long-running Option 1 (native NSTextView) vs Option 2 (WKWebView + JS editor) question. WYSIWYG editing locked over Live Preview at Nathan's direction — typing `**bold**` becomes **bold** instantly, no markers visible. Markdown round-trip via `@tiptap/markdown` (per-node serializers; near-perfect not byte-perfect). `:::callout` and `:::columns` / `@Columns` directives via custom Tiptap `Node.create`. Roadmap reordered: Pages moves from v0.6/0.7/0.8 to v0.3 (internal phases a/b/c); Tabs become v0.4; Properties v0.5; infrastructure cycles shift to v0.6+. Pages open in detail pane (single Page at a time) in v0.3; tabs ship at v0.4. Standalone-window-via-context-menu / `⌥⌘O` path works in v0.3a via `WindowGroup(for: PageRef.self)`. Full implementation spec at `// Planning//Page-Editor-Plan.md`.

**Pre-merge gates verified end-of-session:** `xcodebuild build` SUCCEEDED, 0 warnings; `xcodebuild test -only-testing:PommoraTests` 182/182 pass; sandbox entitlements (`app-sandbox` + `files.user-selected.read-write`) present in built `.app`; Nathan signed off on sidebar + detail pane; CodeRabbit final review: 3 major findings (non-blocking test-coverage; defer to v0.3 prep or small post-merge tightening).

**Merge strategy locked: full history** (non-fast-forward merge commit preserving all 82 commits). Bisect-value-preserving — already paid off twice this session (locating the launch crash, finding SidebarToast issue).

**Known UX gap flagged at session end (2026-05-17):** Item creation affordance is buried — only `CollectionDetailView`'s footer offers "+ New Item"; not in VaultDetailView footer, not in any sidebar context menu. Fix is small (~3 button additions across detail views + row context menus); deferred to pre-v0.3 polish or rolled into v0.3a prep. Sidebar.md table to be updated to reflect the new affordance once added.

**Nathan-sketched "New Item" window design (v0.5 design intent)** captured at `// Features//Items.md` "Item window — design evolution" section. Modal window with 2-column layout (description body LEFT, property dropdowns stacked RIGHT), Delete (red, edit-only) + Save (blue primary) footer, title bar with icon-picker + view-toggle affordances top-right. Supersedes current v0.2 Spartan ItemWindow popover; lands with v0.5 Properties.

**Parallel-session caveat established as project quirk #15:** Nathan may have a separate session running small UI tweaks while another session is working. Pommora/* working tree is no longer guaranteed clean between subagent dispatches; small Nathan-hand-tweaks may appear (e.g., the `0.12 → 0.10` opacity tweak that arrived mid-session). Subagents should never revert unattributed working-tree changes.

---

#### Session 4 — 2026-05-17 end (audit + semver + v0.2.1 / v0.2.2 / v0.2.3 to main)

Long session covering Framework audit + semver conversion + Pages/Tabs reorder + three patches landed on main.

**v0.2.0 merged to main (e3daedb):** the paradigm-scaffolding 83-commit branch merged via `git merge --no-ff` preserving full history. Pushed to `origin/main`.

**Framework audit + reorders (locked end-of-session):**

1. **Pages + Tabs ship as v0.2.x patches, NOT v0.3.0/v0.4.0 minors.** Restructured: v0.2.7 = Pages editor (prose + standard Markdown), v0.2.8 = Tabs, v0.2.9 = directives + heading fold + slash menu, v0.2.10 = wikilinks + rename cascade. Order between v0.2.7 and v0.2.8 is interchangeable. v0.3.0 becomes Properties — the next substantial capability after Pommora is writable + multi-instance.
2. **Editor library NOT solidified.** Tiptap was previously locked in `// Planning//Page-Editor-Plan.md`; demoted to "leading candidate" end-of-session. Final pick reopens at v0.2.7 implementation start. Architecture (WKWebView + 7-message bridge + MarkEdit pattern) stays stack-agnostic.
3. **Agenda UI ships hand-in-hand with EventKit at v0.6.0** — not split. Earlier in the session an Agenda-UI-at-v0.5-split was considered; reverted end-of-session.
4. **SQLite + Watcher at v0.4.0** (was v0.8.0); **Vault views at v0.5.0** (was v0.10.0); **v0.6.0 consolidates** EventKit + Agenda UI + accessibility + performance + onboarding + Settings + accent customization. v0.11/v0.12 dissolved.
5. **`.trash//` data layer at v0.2.5**, in-app Trash UI window at v0.4.0.
6. **Semver format locked:** `major.minor.patch`. Minor = completed feature; patch = touch-up or addition; major reserved for v1.0.0. Internal phases like `v0.3a/b/c` retired.

**Three patches shipped to main (in order):**

1. **`3bcf328` — v0.2.1: Parallel-session sidebar UX tweaks + page selection wiring.** 16 Swift files (Detail / Sidebar / Sheet polish from the parallel Claude session) including `case page(PageMeta)` selection wired + a `PageDetailView`-style placeholder in `SidebarDetailView` ("Page editor coming v0.6" — stale version string, fix in v0.2.6 spec catch-up).
2. **`2e140ed` — v0.2.2: CodeRabbit tightening.** `ItemWindow.swift` refetch-after-rename recovery (`await contentManager.loadAll(for: coll)` + `dismiss()` on still-missing-after-reload) + 2 `ContentManagerTests` filesystem assertions (`renameItem` verifies old URL gone + new URL exists; `deletes` verifies files gone from disk). Cherry-picked from the `v0.2.2-coderabbit` branch (snapshot ref `e462681`). Executed via subagent-driven-development skill: implementer + spec reviewer + quality reviewer.
3. **`56efd68` — v0.2.3: CI baseline.** `.github/workflows/ci.yml` running `xcodebuild build` + `xcodebuild test -only-testing:PommoraTests` on `runs-on: macos-26`, triggered by push to ANY branch + PRs targeting `main`. Cherry-picked from `v0.2.3-ci` branch (snapshot ref `b746481`). First push will smoke-test runner availability; fallback is `macos-latest` + explicit Xcode 26 path.

**Combined build state verified end-of-session:** `xcodebuild build` BUILD SUCCEEDED, 0 source warnings; `xcodebuild test -only-testing:PommoraTests` 182/182 pass.

**Mid-session git incident:** while branching for v0.2.x patches, Claude stashed `.claude/*` doc accumulation + Swift parallel-session edits before branch switch. Nathan saw docs revert to days-old state when his view followed Claude to feature branches off main. Recovered via `git stash pop`. **Lesson:** `.claude/*` IS included in commits (corrected quirk #4). Prior "don't stage .claude/* unless explicitly asked" prevents unilateral doc bundling into Swift commits, but explicit doc commits expected so branch switches preserve doc visibility.

**xcbeautify deferred from CI:** plan included `| xcbeautify --renderer github-actions` pipes; shipped without it as scope reduction — raw `xcodebuild` output sufficient. Future small patch (needs `brew install xcbeautify`).

**Item Window v0.5 redesign now targets v0.3.0:** was slotted with Properties at v0.5.0; Properties moved to v0.3.0, redesign comes along.

**Tomorrow's session opens with:** v0.2.4 swift-format baseline → v0.2.5 `.trash//` data foundation → v0.2.6 spec catch-up → v0.2.7 Pages editor (editor-library decision reopened first). See `Handoff.md`.

---

#### Session 5 — 2026-05-18 (v0.2.4 → v0.2.6 shipped via subagent-driven-development)

Execution session: 4 code patches + 1 doc sweep, ending at v0.2.6 — Pommora has CI + formatter + `.trash//` data layer + spec docs synced, ready for editor-library decision and v0.2.7 Pages. Commits land on `main` directly per Nathan's override ("execute; but let's keep it on this branch"); not pushed (Nathan reviews + pushes).

**Execution model:** `subagent-driven-development` for v0.2.4 / v0.2.5 (implementer + spec-reviewer + code-quality-reviewer chain). Compressed review for v0.2.5.1 / v0.2.6 (already-reviewed Minor items + mechanical updates). Builder subagent for xcodebuild where reachable; piped-log fallback otherwise.

**Five patches shipped:**

1. **`60e2ef6` — v0.2.4: swift-format baseline.** `.swift-format` config at repo root (lineLength 120 / 4-space indent / `respectsExistingLineBreaks: true` / `OrderedImports: true` / `NeverForceUnwrap: false` to honor `try!` use). One-time formatter pass over 97 Swift files (+593/-422; mechanical whitespace + import-ordering only, no semantic changes). CI `swift format lint --strict --recursive` step in `.github/workflows/ci.yml` after "Show toolchain" — fail-fast. Also fixed two pre-existing `OneCasePerLine` violations in `Recurrence.swift` (`Kind` and `Day` enums) since the formatter can't auto-fix that rule — the alternative (disabling the rule) was worse. Code quality reviewer flagged one cosmetic regression: `swift format` mangled ~12 single-line `do { try await … } catch { /* … */ }` patterns in `SidebarView.swift` + `IconPickerSheet.swift` into `} catch\n{ … }` shape (`respectsExistingLineBreaks: true` can't preserve single-line catch bodies that span the `{`). Recommended structural fix (extract `runDelete(_:)` helpers) when SidebarView is next touched — likely during v0.2.7 work; not config-driven.

2. **`9f56fbe` — v0.2.5: `.trash//` data foundation.** 5 new APIs: `NexusPaths.trashDir(in: nexus)` returns `<nexus>/.trash/`; `Filesystem.moveToTrash(_:in:)` (@discardableResult URL throws) preserves the deleted entity's relative path under nexus root, creates intermediate `.trash` dirs, resolves collisions via timestamp suffix; private `Filesystem.suffixedWithTimestamp(_:)` helper; `FilesystemError.sourceNotInNexus(source:, nexus:)` case (new `LocalizedError` enum — no pre-existing type to extend); file-private `String.removingPrefix(_:)` helper. Swapped 10 manager delete call-sites: SpaceManager.delete / TopicManager.deleteTopic + deleteSubtopic / VaultManager.deleteVault + deleteCollection / ContentManager+CRUD.deletePage×2 + deleteItem×2 / AgendaManager.deleteItem. All 10 managers already held a `nexus` reference — no threading required. Pre-existing `pendingError` flow preserved. New `Pommora/PommoraTests/AtomicIO/FilesystemTrashTests.swift` with 4 tests (movesFile / movesFolder / collisionAddsTimestampSuffix / rejectsExternalSource). Extended v0.2.2's `ContentManagerTests.deletes` + `VaultManagerTests.deleteVault`/`deleteCollection` assertions to ALSO check trash-side existence (the cross-patch coordination flagged in the plan). Tests: 182 → 186. PRD-aligned: `.trash//` lives inside the nexus (syncs with iCloud/Dropbox as user data, not regeneratable index), unlike `nexus.db` which lives in Application Support.

3. **`25de7c6` — v0.2.5.1: Trash cleanup.** Three Minor items from the v0.2.5 code quality reviewer: (a) `suffixedWithTimestamp` now appends a 4-char hex discriminator (UUID prefix) after the UTC `YYYYMMDD-HHMMSS` timestamp — guarantees uniqueness for the same-second collision edge case (`@MainActor` serialization makes this impossible today, but future batch-delete scenarios would benefit). Filenames become `Notes.20260518-093215-A3F2.md` — slightly noisier but always unique without loop ceremony. (b) `rejectsExternalSource` test tightened to pattern-match the specific `FilesystemError.sourceNotInNexus` case via the closure form `throws: { error in case ... = error }`, matching existing test convention in `AgendaManagerTests` / `SpaceManagerTests` / `AtomicYAMLMarkdownTests`. (c) UTC documentation folded into the suffix function's docstring (cross-timezone determinism rationale).

4. **`7b17d1d` — v0.2.6: Spec catch-up.** 5 Swift `Text(...)` version strings aligned to Framework reorder: `ItemWindow.swift` "Property-panel relation editor coming v0.5" → "Property panel coming v0.3.0"; `PropertyEditorRow.swift` "Relation editor coming v0.5" → "Relation editor coming v0.3.0"; `ContextDetailPlaceholder.swift` "Composed view coming v0.9" → "Composed view coming v0.7.0" (+ doc comment); `SidebarDetailView.swift` "Saved view coming v0.5" → "Saved view coming v0.6.0"; "Page editor coming v0.6" → "Page editor coming v0.2.7". Doc passes: `// Features//Pages.md` softened "Tiptap LOCKED" → "leading candidate; final pick reopens at v0.2.7 prep" with candidate list (Tiptap / Milkdown / BlockNote / CodeMirror 6); cross-refs Paradigm-Decision #7. `// Features//Sidebar.md` updated right-click table Page row to v0.2.7 + replaced "discoverability deferred to quick-capture" with "hover-icon `+` complement + quick-capture" (spec was stale on what shipped in v0.2.0).

5. **`<pending>` — docs-end-5-18: End-of-session doc sweep.** This `History.md` entry + `Handoff.md` rewrite + `Framework.md` "Current Focus" + v0.2.x "Shipped" expanded for v0.2.4-v0.2.6 + `CLAUDE.md` Active Version table updated + quirk #12 added. `PommoraPRD.md` and `Paradigm-Decisions.md` needed no changes — decision #7 already reflects current state; PRD is version-agnostic.

**Build state end-of-session:** `xcodebuild build` SUCCEEDED, 0 warnings; `xcodebuild test -only-testing:PommoraTests` 186/186 pass; `swift format lint --strict --recursive` exit 0; entitlements present; tree clean.

**No new paradigm-solidifying decisions.** Pure execution + spec hygiene. 10-entry Paradigm-Decisions registry from end-of-5-17 remains current.

**Project quirk added (#12):** `swift format` invoked as subcommand (`swift format format`, `swift format lint`) via Xcode 26's bundled toolchain. Direct `swift-format` binary not on `$PATH`. CI uses same form. Locked at v0.2.4.

**SourceKit staleness re-confirmed (quirk #3):** false "Cannot find type X" + "No such module 'Testing'" diagnostics for same-module types throughout session (`Nexus`, `Space`, `NexusPaths`, `Filesystem`, `NexusContext`, `Item`, `Vault`, `PropertyValue`, `ContentManager`, etc.). xcodebuild consistently passed. Clears after re-indexing.

**Next session opens with:** confirm push of v0.2.4-v0.2.6 to origin (first CI smoke-test on `runs-on: macos-26`; fallback `macos-latest` + Xcode 26 path) → reopen editor library decision via `superpowers:brainstorming` → **v0.2.7 Pages editor** per `// Planning//Page-Editor-Plan.md`. Use `subagent-driven-development`. See `Handoff.md`.

---

#### Session 6 — 2026-05-18 (continued — editor library re-evaluation, no code)

Research session after v0.2.4-v0.2.6 shipped. Nathan reopened editor library decision and pushed for honest evaluation of native AppKit / TextKit 2 against prior Tiptap framing. **No code committed**; outcome is rewritten `// Planning//Page-Editor-Plan.md` (objective options inventory) + chat-only recommendation.

**Skills used:** `superpowers:brainstorming` (framing), `swiftui-expert-skill` (TextKit 2 / `AttributedString` / macOS-views), `context7` (`/swiftlang/swift-markdown` API + source-range tracking + GFM tables + visitor patterns). Background Explore covered WWDC25 Session 280, Bear 2, Drafts, MarkEdit, user-shared Reddit thread, open-source precedents.

**Linchpin clarifier:** Nathan confirmed Live Preview (Obsidian/Bear marker-fade-by-proximity) AND pure WYSIWYG both acceptable — "as long as Markdown syntax isn't always visible and the page looks like a page rather than a file." Removes constraint that drove Tiptap-over-CodeMirror earlier.

**Deep-dive on `Pallepadehat/MarkdownEditor`** (cloned + read full source). 3,010 LOC (~1,300 Swift, ~1,700 TypeScript). MIT, v1.0.1 (Feb 11 2026), 26★, 6 forks. macOS 14+, Swift 5.9+, Xcode 15+. WKWebView + CodeMirror 6 + `@codemirror/lang-markdown` + `@lezer/markdown` GFM. Pre-built `editor.html` ships as SPM Resource via `vite-plugin-singlefile` — no JS toolchain in consumer build. Public Swift API: `EditorWebView(text: Binding<String>, configuration: EditorConfiguration, onReady:)` + `EditorBridge` (`@MainActor`, ~30 methods) + `EditorBridgeDelegate` + `EditorConfiguration` (Codable/Equatable/Sendable, includes `hideSyntax` toggle). Ships: `syntax-hiding.ts` (185 LOC), `command-palette/` (~500 LOC), `math.ts` (386 LOC, KaTeX), `mermaid.ts` (281 LOC), `images.ts` (208 LOC), `calc.ts` (97 LOC), Xcode-themed light/dark, `@codemirror/search`. Doesn't ship: wikilinks, `:::callout`, `@Columns`, visual table rendering, heading fold, bubble menu, Pommora brand theme. Widget extension pattern: walk syntax tree via `syntaxTree(state).iterate()` → `Decoration.mark()`/`Decoration.replace({widget})` to `RangeSetBuilder` → `StateField` via `EditorView.decorations.from(field)` → `Extension` via `Compartment`. Each Pommora widget = new TS file at `CoreEditor/src/widgets/<name>.ts`.

**Reference for native path:** [`nodes-app/swift-markdown-engine`](https://github.com/nodes-app/swift-markdown-engine) (Apache 2.0, 455★, v0.4.0 May 2026). NSTextView + TextKit 2 + SwiftUI bridge. Built by Nodes (Germany), in their commercial macOS app. Ships: live styling, wiki-linking with `[[Name|<id>]]` storage/display round-trip (matches Pommora spec), LaTeX blocks + inline, code blocks with embedder-supplied syntax highlighting, task checkboxes, Writing Tools (macOS 15.1+), spelling/grammar with code/LaTeX/wiki-link suppression, bottom overscroll, drag-select autoscroll. Doesn't ship: tables, multi-column layout, block-level callouts.

**Native framework gaps:**
- TextKit 2 has no native `NSTextTable` support; an `NSTextTable` instance in attributed string triggers fallback to TextKit 1, disabling `NSTextAttachmentViewProvider`. Apple Forums thread 776824. Workaround: render tables via `NSTextAttachment` / `NSTextAttachmentViewProvider`, never `NSTextTable` — fallback isn't triggered by "document contains table syntax," only by NSTextTable instances in storage.
- No multi-column inline layout API in TextKit 2. `@Columns` requires custom rendering. STTextView discussions note custom `NSTextContentManager` is "challenging."
- `swift-markdown` lacks first-class custom-directive parsing. Post-parse traversal handles `:::callout` / `@Columns`.
- `swift-markdown` DOES provide source-range tracking (`element.range.lowerBound.line/column/source`) — critical for decoration efficiency.
- MarkEdit's creators (3.3k★) chose CodeMirror over TextKit 2 citing documentation/community/feature complexity. Production-quality native Markdown editing is non-trivial.

**Three options now in `// Planning//Page-Editor-Plan.md`** (rewrote 939 → 169 lines; objective inventory, no recommendation in doc):
1. **Native Swift** — `swift-markdown` + TextKit 2 + `NSTextView`. Optionally wrap `nodes-app/swift-markdown-engine`.
2. **JS editor library + WKWebView shell we build** — Tiptap (WYSIWYG, ~250KB, MIT) / Milkdown (better round-trip, ~400KB, MIT) / BlockNote (React + GPL/commercial). Shell ~1-2 sessions of standard WebKit work. No Swift Package wrapper exists as of May 2026.
3. **Fork `Pallepadehat/MarkdownEditor`** — CodeMirror 6 + WKWebView. Fork to add Pommora widgets (wikilinks, `:::callout`, `@Columns`, tables, bubble menu, brand theme). Fork is ours; upstream reference only.

**Swap costs in Claude sessions** (per new "effort estimates use Claude-time" rule). Transitions are 1-2 sessions for shell/wrapper swap + 1 session per Pommora widget. `.md` is the firewall — user data portable across all transitions. Reversibility roughly symmetric.

**Chat-only recommendation:** Try Option 3 first. Cheapest experiment (v0.2.7 prose ships in 1 session); surfaces WKWebView-feel question fast; reversibility high (Pallepadehat is clean SPM cut). Session-1 deliverable spec in `Handoff.md`.

**StudioMD updated** with "Effort estimates use Claude-time" rule (Nexus source → Studio deploy). Mandates Claude sessions/hours framing — never weeks/days/months. Sibling bullet to "Frame tradeoffs in plain terms" under "Working with Nathan."

**Nexus mirrors** of `Page-Editor-Plan.md` + Handoff/Framework/CLAUDE/History/Pages to `//The Nexus//Topics//Pommora//`.

**Paradigm-Decisions registry impact:** Decision #7 (Tiptap leading direction) superseded by three-option inventory. Sync at v0.2.7 implementation start.

**Next session opens with:** push v0.2.4-v0.2.6 to origin if Nathan signals → confirm pick among three options (recommendation Option 3) → implement v0.2.7. Opening commit (common to all): `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` mirroring `updateItem`. Session-1 deliverable spec in `Handoff.md`.

---

#### Session 7 — 2026-05-18 (continued — Phase A-G of v0.2.7 + Milkdown decision)

Long execution session. Nathan picked Option 3 (fork Pallepadehat); shipped Phase A through Phase G of v0.2.7 across 11 commits on `main` + 3 commits on the fork at `Natertot215/PageEditorMD`. End-of-session smoke test failed Nathan's visual baseline despite extensive Apple typography overhaul; decision to swap to Milkdown + Crepe (later superseded by Session 8). Doc commit at `152609c`; no swap code.

**Code shipped (11 commits, `1df93a6` → `1989fac`):**

- **Phase A** — SPM dep on Pallepadehat fork.
- **Phase B** — Domain layer: `PageRef` (Codable+Hashable ID-based for `WindowGroup(for:)`), `ContentManager.updatePage(_:body:in:vault:)` + vault-root variant (body-only writes, frontmatter preserved verbatim via `PageFile(...).save(to:)` → `AtomicYAMLMarkdown.write` → atomic temp+rename), `PageEditorViewModel` (300ms debounce, `flushNow`/`close`/`explicitSave`/`clearError`, `PageSaver` protocol + `ContentManagerPageSaver`), 10 new tests + Nathan's icon migration.
- **Phase C1-C5.2** — Inspector wiring + sandbox entitlements (4 keys including `network.client` for WKWebView), `AppGlobals` (NSHashTable<PageEditorViewModel> registry + willResignActive + willTerminate observers), `AppState.pageInspectorOpen` per-Page persistence (v1→v2 backward-compat decoder), `FrontmatterInspector` (read-only Form), `PageEditorView` + `PageEditorHost` (`.task(id:)` page-switch flush + `.id()` re-keying), editable title `TextField` (28pt bold, plain, commit → `ContentManager.renamePage`), inspector at NavigationSplitView level with toolbar `ToolbarItem(placement: .primaryAction)` INSIDE `.inspector(...)` closure (fixes left-side placement), sidebar page-switching fix (`@State var viewModel` → `@Bindable` + `.id(vm.page.id)`).
- **Phase G** — Fork polish: drop active-line, custom fold chevron, `markdown-autopair.ts` for `**`/`__`/`[[`/`` ` ``, Apple typography (SF Pro Text body + SF Pro Display headings + SF Mono code; 28/22/17/15/13/13pt), triple-clear transparent-bg (`drawsBackground=false` KVC + `underPageBackgroundColor=.clear` + NSView layer bg + CSS `!important`), Pommora-side `.background(Color.clear)` defensive layer.

**Build state end-of-session:** `xcodebuild build` SUCCEEDED. `xcodebuild test -only-testing:PommoraTests` → **198/198 pass**. `swift format lint --strict --recursive` → exit 0.

**Smoke test verdict (Nathan):** Phase G's overhaul still didn't produce Notion-like polish. Decision to swap editor library to Milkdown + Crepe. Plan written at `// Planning//v0.2.7-milkdown-swap.md`. Compact at session close.

**Project quirk added (#13 in `CLAUDE.md`):** SPM branch-pinned forks need full cache nuke to bump (gentle `xcodebuild -resolvePackageDependencies` respects pins). Nuke `Package.resolved` + `DerivedData/.../SourcePackages` + `~/Library/Caches/org.swift.swiftpm/repositories/<DepName>-*`.

---

#### Session 8 — 2026-05-18 (continued — architecture pivot to Apple swift-markdown + swift-markdown-engine, plan-only)

Plan-only session. Nathan reconsidered the Milkdown direction after demoing `nodes-app/swift-markdown-engine` (Apache 2.0, native TextKit 2, ~7411 LOC). The demo (built + launched manually by Nathan in Terminal — auto-mode classifier blocked the builder agent from /tmp paths) made the native-Mac feel undeniable. Session produced a comprehensive single-session implementation plan at `// Planning//v0.2.7-engine-swap.md` and Nathan accepted it. No code committed. Compact at session close to execute the plan in one go next session.

**Architecture locked:**

- **Parser:** Apple `swift-markdown` (full GFM AST + `BlockDirective` for v0.2.9 directives + source-range tracking). SPM dep on `swiftlang/swift-markdown`.
- **Renderer:** Apple `NSAttributedString` + `NSTextView` + `NSTextLayoutManager`. Writing Tools (15.1+), Look Up / Translate / spell-check, IME, dynamic system colors, drag-select all free.
- **Live-preview chassis:** `swift-markdown-engine` (selectively vendored at `Pommora/Pommora/PageEditor/Engine/`, ~4500 LOC after planned deletions). Two load-bearing engine contributions: **dynamic syntax** (markers shrink when caret leaves AST node — Bear/Notion pattern) + **Markdown-aware typing helpers** (list continuation + block auto-wrap shipped; character-pair auto-pair `**`/`__`/`[[`/`` ` `` with auto-exit-on-space added Pommora-side in Phase 4.5). Engine's `Services/WikiLinkService.swift` two-form `[[Name|<id>]]` ↔ `[[Name]]` storage transform also kept as reference for v0.2.10 wikilink work.
- **Domain wiring:** PageRef, PageFile, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, inspector + sidebar wiring, lifecycle observers, atomic-write contract, frontmatter preservation rule, editable title TextField, all 198 tests — **survive unchanged from Phase A-G**.

**Critical scoping discovery:** engine's `MarkdownToken` type is load-bearing — 11 non-styling files (coordinator extensions, ContextMenu, SpellingPolicy, Input handlers) reach through it. Plan **preserves type-API** of `MarkdownToken`/`MarkdownTokenizer.parseTokens(in:)`/`MarkdownDetection.isInside…` and **rewrites internals** to back onto Apple AST. Only `MarkdownStyler` gets a full body swap (replaced by `PommoraMarkdownStyler`).

**Plan structure (single session, Phases 0-5; Phase 6 docs split defers to v0.2.7.1):**

- **Phase 0** — Docs repair (~30min) — verify Handoff/History/Framework/CLAUDE reflect reality post-compact.
- **Phase 1** — Strip Pallepadehat fork (~30min) — 6 pbxproj entries + Package.resolved + `import MarkdownEditor` + `pommoraEditorConfig` + `EditorWebView` call + `network.client` entitlement + `External/PageEditorMD/` clone.
- **Phase 2** — Vendor engine + Apple swift-markdown SPM (~45min) — drop `MarkdownEngine.docc/`; copy engine; pin Apple swift-markdown.
- **Phase 3** — Parser internals + styler (~2h, the heart) — reimplement `MarkdownTokenizer.parseTokens(in:)` as Apple-AST walker emitting `MarkdownToken` shims; reimplement `MarkdownDetection` helpers; write `PommoraMarkdownStyler` (all GFM block types); `PommoraInlineScanner` for wikilink/image-embed overlay; `SourceRangeToNSRange` converter + tests.
- **Phase 4** — Wire PageEditorView (~20min) — replace `EditorWebView` with `NativeTextViewWrapper`; swap config; title TextField untouched.
- **Phase 4.5** — Auto-pair + auto-exit-on-space (~30min core + 20min stretch) — extend `MarkdownInputHandler`.
- **Phase 5** — Smoke-test (~15min) — type prose / table / blockquote / hr / strikethrough / wikilink; switch Pages; verify on disk.
- **Phase 6** — Docs split → defer to v0.2.7.1.

**Locked execution rules:** all commits on `main` directly (override of quirk #13); every dispatched agent uses `claude-opus-4-7` (Opus 4.7); `builder` subagent for `xcodebuild`; FILENAME form for `-only-testing` (quirk #1); `swift format lint --strict` exit 0 before every commit; Nathan pushes manually.

**End-of-session state:** code state unchanged at `152609c`; build green; 198/198 tests pass; lint clean. Planning folder: `v0.2.7-engine-swap.md` active; `v0.2.7-milkdown-swap.md` deleted by Nathan as no-longer-needed; Pallepadehat-era `v0.2.7-editor-polish.md` already marked SUPERSEDED.

**Next session opens with:** post-compact, execute the engine-swap plan Phases 0-5 in one go per the verbatim resume prompt at the top of `Handoff.md`.
