### Pommora — Domain Paradigm Scaffolding Plan (Phases 0 → 6)

> **🟢 SHIPPED 2026-05-17** — all 65 tasks landed across two sessions (2026-05-16 + 2026-05-17). Branch `paradigm-scaffolding`, 69 commits ahead of `main`. 177 unit tests, 0 failures, 0 source warnings, sandbox entitlements verified. Awaiting Nathan's manual gold-path verification + 4-commit pre-merge cleanup (see `Handoff.md` for the cleanup plan) before squash-merge.
>
> Mid-plan paradigm decisions surfaced during implementation are logged in `// Guidelines//Paradigm-Decisions.md`:
> - PropertyValue.relation tagged `{$rel}` encoding (2026-05-16)
> - Collection `_collection.json` sidecar (2026-05-16, supersedes original spec's "no metadata file")
> - SymbolPicker SPM dep behind `IconPickerSheet` wrapper (2026-05-16)
> - Stub-and-progressively-replace execution strategy (2026-05-17, supersedes the spec's batch-commit-at-end approach)
> - Sidebar UX direction — right-click context menus replace "+ New" buttons (2026-05-17, supersedes spec's footer-button layout)

#### Context

Pommora's `main` is clean at v0.1a Nexus Foundation (shipped) + sidebar visual scaffolding (committed). The RC session before this plan landed the locked 2-layer PARA domain model (Contexts / Vaults / Agenda / Homepage), rewrote the full doc set, and ran a pre-plan validation pass against Yams / GRDB / EventKit / SwiftUI APIs (corrections live at [.claude/Planning/Contexts-Vaults-spec.md:1187-1247](.claude/Planning/Contexts-Vaults-spec.md#L1187-L1247)).

This plan scaffolds the entire paradigm — every locked entity becomes real Swift code with end-to-end CRUD UI, except for the surfaces that genuinely depend on later infrastructure (composed-blocks editor, Markdown editor, EventKit, file watcher, SQLite). Scope corresponds to **Phases 0 → 6** of the implementation spec:

- Phase 0 — Codable foundation for every entity
- Phase 1 — Filesystem primitives + validation engine
- Phase 2 — Spaces CRUD + sidebar
- Phase 3 — Topics CRUD + sidebar
- Phase 4 — Sub-topics CRUD
- Phase 5 — Vaults + Collections CRUD + sidebar
- Phase 6 — Content CRUD (Pages create/rename/delete; Items create/rename/delete + Item Window popover)
- Agenda + Homepage scaffolded (data layer only; full UI follows in v0.4 / v0.9)

End-state: the four-section sidebar (Saved / Spaces / Topics / Vaults) is fully live; the whole locked domain model exists on disk in the documented JSON/Markdown shapes; create / rename / delete works end-to-end for every Context entity, every Vault + Collection, and every Page + Item; Items open in the Item Window popover for basic property + description editing; Agenda + Homepage files exist on disk with seeded defaults.

#### Locked decisions from this brainstorm

- **Plan scope:** Phases 0 → 6 of the implementation spec; CRUD UI for Contexts + Vaults + Collections + Pages + Items; data-layer scaffold for Agenda + Homepage. No tabs, no editors, no EventKit, no watcher, no Settings scene, no `tier1/2/3` relations property panel (Phase 7), no composed-blocks rendering (v0.9).
- **Swift 6 migration:** flip `SWIFT_VERSION = 6` + `SWIFT_STRICT_CONCURRENCY = complete` at the start. If migration surfaces > 30 min of friction, pause and report.
- **Topic delete behavior:** Sub-topics **promote to Topics** by default; cascade-delete is an explicit second destructive option in the confirmation dialog. Promoted Topic inherits the deleted Topic's parent Spaces. Filename collisions auto-suffix `(2)`, `(3)`, ….
- **Filename collisions on creation:** user-facing `+ New …` flows **reject + surface the error** (user re-types). Auto-suffix is reserved for system-driven moves (Topic-promote, future Page/Item moves between Vaults).
- **Detail pane behavior** (no tabs, no editors): clicking a Space / Topic / Sub-topic / Vault / Collection updates a `SidebarSelection` value; the detail pane shows a minimal "{Title} — composed view coming v0.9" placeholder for Contexts and a basic contents-listing for Vaults / Collections. Clicking a Page does nothing in this plan (no opening surface yet; visible via Finder). Clicking an Item opens the Item Window popover.

#### Step 1 — Swift 6 strict-concurrency migration (upfront)

**Modify:**
- [Pommora/Pommora.xcodeproj/project.pbxproj](Pommora/Pommora.xcodeproj/project.pbxproj) — `SWIFT_VERSION = 6.0` and `SWIFT_STRICT_CONCURRENCY = complete` on both app + test targets.

**Audit:**
- [Pommora/Pommora/Nexus/](Pommora/Pommora/Nexus/) — `NexusManager` already `@MainActor @Observable`; value types should pass clean.
- [Pommora/Pommora/Sidebar/](Pommora/Pommora/Sidebar/) — `View` structs are `Sendable` by construction.
- Hot spots: `Task { … }` captures in `NexusManager.openExisting` and `pickNexus` paths — annotate with `@MainActor` where needed; no `Sendable` workarounds.

**Verify:** `xcodebuild build` succeeds with zero warnings. All 26 existing tests pass.

#### Step 2 — Foundation helpers

**Add dependency (SwiftPM):** `https://github.com/jpsim/Yams.git`, `from: "5.1.0"`. Used by Phase 6's Page frontmatter; registered here so later phases don't block on dependency management.

**Create:**
- `Pommora/Pommora/AtomicIO/AtomicJSON.swift` — generic Codable wrapper over `Data.write(.atomic)`. `[.prettyPrinted, .sortedKeys]` + ISO-8601 dates. Spec at [.claude/Guidelines/CRUD-Patterns.md:66-89](.claude/Guidelines/CRUD-Patterns.md#L66-L89).
- `Pommora/Pommora/AtomicIO/AtomicYAMLMarkdown.swift` — YAML-frontmatter + Markdown-body file shape: `load(from:) -> (frontmatter: Decodable, body: String)` and `write(frontmatter:body:to:)`. Splits on the leading `---\n` / trailing `\n---\n` envelope. Pattern at [.claude/Guidelines/CRUD-Patterns.md:101-120](.claude/Guidelines/CRUD-Patterns.md#L101-L120).
- `Pommora/Pommora/AtomicIO/NexusPaths.swift` — every path the paradigm uses:
  - `nexusConfigDir(in:)` → `<nexus>/.nexus`
  - `spacesDir(in:)` → `<nexus>/.nexus/spaces`
  - `topicsDir(in:)` → `<nexus>/.nexus/topics`
  - `tierConfigURL(in:)`, `savedConfigURL(in:)`, `homepageURL(in:)`
  - `agendaDir(in:)` → `<nexus>/Agenda`, `agendaSchemaURL(in:)` → `<nexus>/Agenda/_agenda.json`
  - `spaceFileURL(for:in:)`, `topicFolderURL(for:in:)`, `topicMetadataURL(for:in:)`, `subtopicFileURL(for:in:)`
  - `vaultFolderURL(for:in:)`, `vaultMetadataURL(for:in:)`, `collectionFolderURL(for:vault:in:)`, `pageFileURL(for:in:)`, `itemFileURL(for:in:)`, `agendaItemFileURL(for:in:)`
  - `ensureDirectoryExists(_:)`
- `Pommora/Pommora/AtomicIO/Filesystem.swift` — folder create/rename/delete primitives. Folder rename via `FileManager.moveItem(at:to:)`. Folder-plus-metadata-file atomicity per [.claude/Guidelines/CRUD-Patterns.md:252-275](.claude/Guidelines/CRUD-Patterns.md#L252-L275) — best-effort rollback on metadata-write failure.

#### Step 3 — Codable types for every entity (Phase 0)

**Create folder `Pommora/Pommora/Contexts/`:**
- `SpaceColor.swift` — 9-case enum (gray/brown/orange/yellow/green/blue/purple/pink/red) + `swiftUIColor` property.
- `Space.swift` — `id`, `tier = 1`, `title` (from filename), `color`, `icon`, `blocks: [ContextBlock]`, `modifiedAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:222-237](.claude/Planning/Contexts-Vaults-spec.md#L222-L237).
- `Topic.swift` — `id`, `tier = 2`, `title` (from folder name), `parents: [String]` (Space IDs), `icon`, `blocks`, `modifiedAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:239-254](.claude/Planning/Contexts-Vaults-spec.md#L239-L254).
- `Subtopic.swift` — `id`, `tier = 3`, `title` (from filename), `parents: [String]` (single Topic ID by spec rule), `linkedRelations: [String]`, `icon`, `blocks`, `modifiedAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:256-272](.claude/Planning/Contexts-Vaults-spec.md#L256-L272).
- `ContextBlock.swift` — empty placeholder struct (`{}`); composed-blocks editor lands v0.9. All Context entities carry `blocks: [ContextBlock]` so the schema is stable.
- `TierConfig.swift` — Codable per [.claude/Planning/Contexts-Vaults-spec.md:274-289](.claude/Planning/Contexts-Vaults-spec.md#L274-L289). Seeded with defaults on first load.
- `SavedConfig.swift` — Codable per [.claude/Planning/Contexts-Vaults-spec.md:291-302](.claude/Planning/Contexts-Vaults-spec.md#L291-L302). Seeded with defaults (homepage / calendar / recents) on first load.

**Create folder `Pommora/Pommora/Vaults/`:**
- `PropertyType.swift` — enum: `number`, `checkbox`, `date`, `datetime`, `select`, `multiSelect`, `relation`, `url`. Per [.claude/Features/Properties.md](.claude/Features/Properties.md).
- `PropertyDefinition.swift` — `name`, `type: PropertyType`, type-specific config (`numberFormat?`, `dateIncludesTime?`, `selectOptions?`, `relationScope?`).
- `Vault.swift` — `id`, `icon`, `properties: [PropertyDefinition]` (empty in v1 default; full editor v1.x), `views: [VaultView]` (empty placeholder), `modifiedAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:513-525](.claude/Planning/Contexts-Vaults-spec.md#L513-L525).
- `VaultView.swift` — empty placeholder; views land v0.10.
- `Collection.swift` — value type derived from folder URL; no on-disk metadata file in v1. Fields: `id` (derived from folder URL hash for stable identity in-app), `vaultID`, `title` (from folder name), `folderURL`. Per [.claude/Planning/Contexts-Vaults-spec.md:531-535](.claude/Planning/Contexts-Vaults-spec.md#L531-L535).

**Create folder `Pommora/Pommora/Content/`:**
- `Item.swift` — `id`, `icon`, `description` (250-char cap), `tier1`, `tier2`, `tier3`, `properties: [String: PropertyValue]`, `createdAt`, `modifiedAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:537-554](.claude/Planning/Contexts-Vaults-spec.md#L537-L554).
- `PageFrontmatter.swift` — `id`, `icon`, `tier1`, `tier2`, `tier3`, `properties: [String: PropertyValue]`, `createdAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:556-570](.claude/Planning/Contexts-Vaults-spec.md#L556-L570).
- `PageFile.swift` — composes `PageFrontmatter` + raw `body: String`; uses `AtomicYAMLMarkdown` for load/save.
- `PropertyValue.swift` — type-erased `enum` matching `PropertyType` cases (`.number(Double)`, `.checkbox(Bool)`, `.date(Date)`, etc.). Custom `Codable` so per-vault schemas round-trip cleanly.

**Create folder `Pommora/Pommora/Agenda/`:**
- `AgendaItem.swift` — full schema per [.claude/Features/Agenda.md:39-75](.claude/Features/Agenda.md#L39-L75): `id`, `icon`, `start_at`, `end_at`, `all_day`, `due_at`, `due_floating`, `due_all_day`, `completed`, `completed_at`, `location`, `recurrence: Recurrence?`, `alarmOffsets`, `alarmAbsolute`, `syncTarget`, `calendarID`, `eventkitUUID`, `description`, `tier1`, `tier2`, `tier3`, `createdAt`, `modifiedAt`, `properties`.
- `Recurrence.swift` — Codable matching the corrected EKRecurrenceRule shape at [.claude/Planning/Contexts-Vaults-spec.md:384-412](.claude/Planning/Contexts-Vaults-spec.md#L384-L412): `frequency`, `interval`, `firstDayOfWeek`, `end: RecurrenceEnd?`, `daysOfWeek: [RecurrenceDayOfWeek]`, `daysOfMonth`, `daysOfYear`, `weeksOfYear`, `monthsOfYear`, `setPositions`.
- `AgendaSchema.swift` — Codable schema sidecar (`_agenda.json`) with built-in `type` Select property per [.claude/Planning/Contexts-Vaults-spec.md:429-455](.claude/Planning/Contexts-Vaults-spec.md#L429-L455).

**Create folder `Pommora/Pommora/Homepage/`:**
- `Homepage.swift` — singleton Codable: `schemaVersion`, `icon`, `blocks: [ContextBlock]`, `modifiedAt`. Schema at [.claude/Planning/Contexts-Vaults-spec.md:306-324](.claude/Planning/Contexts-Vaults-spec.md#L306-L324).

#### Step 4 — Validation engine (Phase 1)

**Create:**
- `Pommora/Pommora/Validation/Validators.swift` — pure-function validators per entity. Each `validate(_:in:)` takes the entity + context (existing entities for collision checks) and throws a typed `ValidationError`:
  - `SpaceValidator` — title non-empty, no `/ \ :`, case-insensitive unique within nexus.
  - `TopicValidator` — title rules; `parents` (each must resolve to a Space).
  - `SubtopicValidator` — title rules; `parents.count == 1`; parent must resolve to a Topic; file location must equal parent Topic's folder.
  - `VaultValidator` — title rules; case-insensitive unique within nexus root.
  - `CollectionValidator` — title rules; unique within parent Vault.
  - `ItemValidator` — title rules; unique within parent Collection; `tier1/2/3` IDs each resolve to the right tier; property values conform to Vault schema.
  - `PageValidator` — same as Item, plus `created_at` present.
  - `AgendaValidator` — title rules; if `start_at` set, `end_at` required and `≥ start_at`; `all_day` requires `start_at`; `due_all_day` requires `due_at`; `type` property required and matches `_agenda.json` schema.
  - `HomepageValidator` — singleton (only one file at the known location).

- `Pommora/Pommora/Validation/ULIDValidator.swift` — verify any string passed as an ID matches the ULID 26-char Crockford alphabet.

**Validation discipline:** every manager's `create` / `rename` / `move` calls the appropriate validator before any filesystem mutation. Invalid input throws and surfaces inline in the originating sheet / row.

#### Step 5 — Per-entity managers (Phase 2 onward)

All managers `@MainActor @Observable final class`, initialised with the active `Nexus`, register no security-scoped access (inherit `NexusManager`'s scope). Pattern at [.claude/Guidelines/CRUD-Patterns.md:9-37](.claude/Guidelines/CRUD-Patterns.md#L9-L37).

**Create:**
- `Pommora/Pommora/Contexts/SpaceManager.swift` — `spaces: [Space]`, `pendingError`. Methods: `loadAll`, `create(name:color:icon:)`, `rename(_:to:)`, `updateColor(_:to:)`, `updateIcon(_:to:)`, `delete(_:)`. Spec at [.claude/Planning/Contexts-Vaults-spec.md:1066-1088](.claude/Planning/Contexts-Vaults-spec.md#L1066-L1088).
- `Pommora/Pommora/Contexts/TopicManager.swift` — `topics: [Topic]`, `subtopics: [String: [Subtopic]]` keyed by parent Topic ID. Methods: `loadAll`, `createTopic(name:parents:icon:)`, `renameTopic(_:to:)`, `updateTopicParents(_:to:)`, `updateTopicIcon(_:to:)`, `deleteTopic(_:promotingSubtopics:)` (promote = default; pass `promotingSubtopics: false` for cascade), `createSubtopic(name:inTopic:icon:)`, `renameSubtopic(_:to:)`, `moveSubtopic(_:toTopic:)`, `deleteSubtopic(_:)`. Folder+file atomicity per the rollback pattern at [.claude/Guidelines/CRUD-Patterns.md:252-275](.claude/Guidelines/CRUD-Patterns.md#L252-L275). Topic promote-Subtopic flow described in spec section "Topic delete behavior" (locked in this plan's decisions).
- `Pommora/Pommora/Vaults/VaultManager.swift` — `vaults: [Vault]`, `collections: [String: [Collection]]` keyed by Vault ID. Methods: `loadAll`, `createVault(name:icon:)`, `renameVault(_:to:)`, `updateVaultIcon(_:to:)`, `deleteVault(_:)`, `createCollection(name:inVault:)`, `renameCollection(_:to:)`, `deleteCollection(_:)`. Delete confirmation reports cascade counts (Vault → N Collections + M Items + K Pages).
- `Pommora/Pommora/Content/ContentManager.swift` — single manager handling Pages + Items inside a Collection. `pages: [String: [PageFileMeta]]` and `items: [String: [Item]]`, both keyed by Collection folder URL string. Methods: `loadAll(for: Collection)`, `createPage(name:in:)` (creates `.md` with frontmatter scaffold: id + empty tier1/2/3 + empty properties), `createItem(name:in:)`, `renamePage`, `renameItem`, `updateItem(_:with:)` (Item Window writes), `deletePage`, `deleteItem`. Move-strip rule deferred (no cross-Vault moves in this plan).
- `Pommora/Pommora/Agenda/AgendaManager.swift` — data-only scaffold. Methods: `loadAll`, `createItem(_:)`, `updateItem(_:)`, `deleteItem(_:)`. Seeds `_agenda.json` on first run if missing. Schema validation runs through `AgendaValidator`. No EventKit sync; no UI surface in this plan.
- `Pommora/Pommora/Homepage/HomepageManager.swift` — singleton manager. `homepage: Homepage`. Methods: `load()` (seeds default if `.nexus/homepage.json` missing), `save()`. No editor in this plan; the file exists on disk so the rest of the system can reference it.
- `Pommora/Pommora/Configuration/TierConfigManager.swift` — `config: TierConfig`. `load()` (seeds default if missing), `save()`. No UI yet; defaults stand in.
- `Pommora/Pommora/Configuration/SavedConfigManager.swift` — same pattern for `SavedConfig`.

**Coordinator helpers (lightweight, no class):** validators take a `NexusContext` value containing the relevant manager references for cross-entity lookups (Subtopic creation needs `TopicManager`; Page validation needs `VaultManager` + `TierConfig` lookups). Avoids a heavyweight `NexusCoordinator` class per [.claude/Guidelines/CRUD-Patterns.md:305-317](.claude/Guidelines/CRUD-Patterns.md#L305-L317).

#### Step 6 — Sidebar UI replacement

**Modify:** [Pommora/Pommora/Sidebar/SidebarView.swift](Pommora/Pommora/Sidebar/SidebarView.swift) — replace ALL hardcoded placeholders with a real four-section List:

- `SavedSection` — three fixed rows reading labels from `SavedConfigManager`. Click is a no-op for now (Homepage / Calendar / Recents views land in v0.5).
- `SpacesSection` — `ForEach(spaceManager.spaces) { SpaceRow(...) }` flat rows + "+ New Space" footer button. Color/icon indicator per [.claude/Planning/Contexts-Vaults-spec.md:152-156](.claude/Planning/Contexts-Vaults-spec.md#L152-L156).
- `TopicsSection` — `ForEach(topicManager.topics)` rendering each as `DisclosureGroup` whose content is its Sub-topics. Tagging indicator (color dot v1 default) shows parent Spaces. "+ New Topic" + per-Topic "+ New Sub-topic" inside expanded disclosure.
- `VaultsSection` — `ForEach(vaultManager.vaults)` rendering each as `DisclosureGroup` whose content is its Collections (leaf rows in v1 — Collection contents shown in main pane on click, not nested in sidebar).

**Create extracted row views (one struct per row type — extracted-as-struct discipline per [.claude/Guidelines/CRUD-Patterns.md:354-358](.claude/Guidelines/CRUD-Patterns.md#L354-L358)):**
- `Pommora/Pommora/Sidebar/SpaceRow.swift`
- `Pommora/Pommora/Sidebar/TopicRow.swift` (handles its own disclosure + nested SubtopicRows)
- `Pommora/Pommora/Sidebar/SubtopicRow.swift`
- `Pommora/Pommora/Sidebar/VaultRow.swift` (handles its own disclosure + nested CollectionRows)
- `Pommora/Pommora/Sidebar/CollectionRow.swift`

Each row wraps the locked `SelectableRow` and owns inline-rename state via `@State editingID + draft + @FocusState`, with `.onKeyPress(.escape)` cancel — pattern at [.claude/Guidelines/CRUD-Patterns.md:198-231](.claude/Guidelines/CRUD-Patterns.md#L198-L231). Right-click context menu per row: Rename / [type-specific actions: Change Color, Change Icon, Change Parents] / Delete.

**Selection model:**
- `Pommora/Pommora/Sidebar/SidebarSelection.swift` — `enum`: `.space(Space)`, `.topic(Topic)`, `.subtopic(Subtopic)`, `.vault(Vault)`, `.collection(Collection)`, `.savedKey(String)`, `.none`. Single source of truth held in `ContentView`; rows bind to it.

#### Step 7 — Sheets, pickers, confirmations

**Create folder `Pommora/Pommora/Sidebar/Sheets/`:**
- `SidebarSheet.swift` — `enum SidebarSheet: Identifiable` per [.claude/Guidelines/CRUD-Patterns.md:168-192](.claude/Guidelines/CRUD-Patterns.md#L168-L192). Cases: `.newSpace`, `.newTopic`, `.newSubtopic(parent: Topic)`, `.newVault`, `.newCollection(vault: Vault)`, `.newPage(collection: Collection)`, `.newItem(collection: Collection)`, `.editTopicParents(Topic)`, `.editIcon(SidebarSelection)`, `.editColor(Space)`.
- `NewSpaceSheet.swift` — Form: name `TextField` + `SpaceColorPicker` + SF Symbol `TextField`. Toolbar Cancel / Create. Reads `@Environment(SpaceManager.self)`. Spec at [.claude/Planning/Contexts-Vaults-spec.md:1090-1130](.claude/Planning/Contexts-Vaults-spec.md#L1090-L1130).
- `NewTopicSheet.swift` — name + parent-Space multi-picker (chips from `SpaceManager.spaces`) + SF Symbol field. Validation: at least zero parents allowed (per spec; can be Space-less). Toolbar Cancel / Create.
- `NewSubtopicSheet.swift` — pre-bound to parent Topic from the trigger; name + SF Symbol field.
- `NewVaultSheet.swift` — name + SF Symbol field. Property schema editor deferred (v1.x).
- `NewCollectionSheet.swift` — pre-bound to parent Vault; name only.
- `NewPageSheet.swift` — pre-bound to parent Collection; name only. Creates `.md` with frontmatter scaffold (id, tier1/2/3 empty, properties empty) + empty body.
- `NewItemSheet.swift` — pre-bound to parent Collection; name only. Creates `.json` with `id`, empty `description`, empty tier1/2/3, empty `properties`.
- `EditTopicParentsSheet.swift` — multi-picker over Spaces; save triggers `TopicManager.updateTopicParents`.
- `IconPickerSheet.swift` — minimal `TextField` for SF Symbol name + live preview. Full curated picker deferred per [.claude/Guidelines/CRUD-Patterns.md:331-336](.claude/Guidelines/CRUD-Patterns.md#L331-L336).
- `ColorPickerSheet.swift` — 9-button grid over `SpaceColor.allCases`.
- `SpaceColorPicker.swift` — reusable inline color picker (used in `NewSpaceSheet` and `ColorPickerSheet`).

**Confirmation dialogs (inline `.confirmationDialog` per row):**
- Space delete → "Delete Space {title}?" (no cascade since Spaces don't structurally contain Topics — Topic parents update independently). Validator-side: deleting a Space removes its ID from any Topic's `parents` array on the way out.
- Topic delete → two destructive buttons per locked decision: "Delete Topic & Promote N Sub-topic(s)" (default) and "Delete Topic & All Sub-topics" (cascade).
- Sub-topic delete → "Delete Sub-topic {title}?".
- Vault delete → "Delete Vault {title}? Contains N Collection(s), M Page(s) + K Item(s)." Cascade-delete only (no promote concept for Vault contents).
- Collection delete → "Delete Collection {title}? Contains N Page(s) + M Item(s)." Cascade.
- Page / Item delete → simple confirm.

#### Step 8 — Detail pane behavior (Finder-style native Table for Vaults + Collections)

**Modify:** [Pommora/Pommora/ContentView.swift](Pommora/Pommora/ContentView.swift):
- Hold `@State private var sidebarSelection: SidebarSelection = .none` and pass via environment to both sidebar and detail.
- Detail pane swaps `Color.clear` for `SidebarDetailView(selection:)`.

**Create:**
- `Pommora/Pommora/Detail/SidebarDetailView.swift` — switches on `SidebarSelection`:
  - `.space(let s)` / `.topic(let t)` / `.subtopic(let s)` → `ContextDetailPlaceholder(title:)` — minimal "{Title} — composed view coming v0.9" + the entity's icon, color tag, parents, and a small list of its `linked_relations` if it's a Sub-topic.
  - `.vault(let v)` → `VaultDetailView(vault:)` — native SwiftUI `Table` of contained Collections; title + icon header; footer "+ New Collection" button. No toolbar (per the validation-only intent of this view in v1).
  - `.collection(let c)` → `CollectionDetailView(collection:)` — native SwiftUI `Table` of contained Pages + Items mixed; title + icon header; footer "+ New Page" / "+ New Item" buttons. No toolbar.
  - `.savedKey(...)` → placeholder "Saved view coming v0.5".
  - `.none` → empty-state placeholder.

- `Pommora/Pommora/Detail/ContextDetailPlaceholder.swift`
- `Pommora/Pommora/Detail/VaultDetailView.swift` — SwiftUI `Table(vaultManager.collections[vault.id] ?? [])` with three columns: **Name** (icon + title), **Items** (Page + Item count), **Modified** (folder mtime). Row tap → `sidebarSelection = .collection(...)`. Right-click row → context menu (Rename / Delete) reused from the sidebar's CollectionRow.
- `Pommora/Pommora/Detail/CollectionDetailView.swift` — SwiftUI `Table` over a merged stream of `[ContentItem]` where `ContentItem` is a small `enum { case page(PageFileMeta); case item(Item) }`. Three columns: **Name** (icon + title), **Kind** ("Page" / "Item"), **Modified**. Row tap on a Page is a no-op (no opening surface yet — Markdown editor is v0.6); row tap on an Item opens the Item Window popover. Right-click row → context menu (Rename / Delete) from the sidebar's content rows.

**Why Table and not column/gallery views in this plan:**

- The validation goal — "sidebar selection works + contents appear" — is fully satisfied by one native view; Table is the lowest-friction option, ships out of the box in SwiftUI, sorts and resizes for free, and reads as "Finder-like" without bridging AppKit.
- Column view (Finder-style multi-column browser, à la NSBrowser) has no native SwiftUI equivalent on macOS 26.4 — building it cleanly belongs with the full v0.10 view-types work, not the paradigm-scaffolding pass.
- Gallery view requires thumbnail generation per file kind (Items don't have a representative image yet; Pages don't either); the work fits with v0.10's `cards` + `gallery` modes, which depend on per-Vault property-driven cover-image selection that doesn't exist in this plan.
- All five view modes (table / board / list / cards / gallery) are already locked for v0.10 per [.claude/Framework.md:96-98](.claude/Framework.md#L96-L98); they land together with the view-config UI, saved per-Vault views, and per-view filter/sort/group controls. Splitting two of them into this plan would orphan their toolbar / view-config dependencies.

#### Step 9 — Item Window popover (Phase 6 deliverable)

**Create folder `Pommora/Pommora/ItemWindow/`:**
- `ItemWindow.swift` — sheet-like popover (SwiftUI `.popover` or `.sheet`; pick `.sheet` for Mac since popovers are tricky for forms). Fields:
  - Title (filename = title; editable, triggers `ContentManager.renameItem`).
  - Icon picker (`TextField`).
  - Description `TextEditor` (250-char cap with counter).
  - Properties section — `ForEach(vault.properties) { PropertyEditorRow(definition:, value: binding) }` reading the parent Vault's schema. Each row renders the right control per `PropertyType`.
  - Footer: ULID + created/modified timestamps (read-only).
- `Pommora/Pommora/ItemWindow/PropertyEditorRow.swift` — switches on `PropertyType`, renders `TextField` (number/url), `Toggle` (checkbox), `DatePicker` (date/datetime), `Picker` (select), `MultiSelectChips` (multi-select), placeholder "Relation editor coming v0.5" (relation — out of scope this plan).
- `Pommora/Pommora/ItemWindow/MultiSelectChips.swift` — chips control over a list of options with add/remove.

**Tier1/2/3 relation editing is NOT in this plan** (Phase 7 of spec, v0.5 of Framework). The Item Window shows tier1/2/3 IDs as read-only ULID strings with a "coming v0.5" note.

#### Step 10 — ContentView wiring

**Modify:** [Pommora/Pommora/PommoraApp.swift](Pommora/Pommora/PommoraApp.swift) — no scene-level changes beyond keeping the existing `InspectorCommands()` and Open Nexus / Debug menus.

**Modify:** [Pommora/Pommora/ContentView.swift](Pommora/Pommora/ContentView.swift) — when `nexusManager.currentNexus` becomes non-nil, construct all managers as `@State` values keyed off that nexus and inject via `.environment(...)`:

```
@State private var spaceManager: SpaceManager?
@State private var topicManager: TopicManager?
@State private var vaultManager: VaultManager?
@State private var contentManager: ContentManager?
@State private var agendaManager: AgendaManager?
@State private var homepageManager: HomepageManager?
@State private var tierConfigManager: TierConfigManager?
@State private var savedConfigManager: SavedConfigManager?
```

All managers (re)build inside `.onChange(of: nexusManager.currentNexus)`. Inject only the non-nil ones into the environment. Sidebar + detail views read via `@Environment(Manager.self)`.

#### Step 11 — Tests

**Create:**
- `Pommora/PommoraTests/AtomicJSONTests.swift` — round-trip a sample Codable; verify `[.atomic]` + sorted keys.
- `Pommora/PommoraTests/AtomicYAMLMarkdownTests.swift` — frontmatter parse/serialise round-trip; missing-frontmatter graceful; body-only file produces empty frontmatter.
- `Pommora/PommoraTests/NexusPathsTests.swift` — every path helper returns the expected URL relative to a temp nexus.
- Per-entity Codable round-trip tests:
  - `SpaceFileTests`, `TopicFileTests`, `SubtopicFileTests`, `VaultFileTests`, `ItemFileTests`, `PageFileTests`, `AgendaItemFileTests`, `RecurrenceTests`, `HomepageFileTests`, `TierConfigTests`, `SavedConfigTests`.
- Validator tests: one file per validator covering every rule (`SpaceValidatorTests`, `TopicValidatorTests`, `SubtopicValidatorTests`, `VaultValidatorTests`, `CollectionValidatorTests`, `ItemValidatorTests`, `PageValidatorTests`, `AgendaValidatorTests`, `HomepageValidatorTests`).
- Per-manager lifecycle tests (temp nexus, no real bookmark): `SpaceManagerTests`, `TopicManagerTests` (includes promote-vs-cascade Subtopic on Topic delete), `VaultManagerTests`, `ContentManagerTests`, `AgendaManagerTests`, `HomepageManagerTests`, `TierConfigManagerTests`, `SavedConfigManagerTests`.

End state: existing 26 tests + ~40 new tests, all passing.

#### Sequencing

Build phase-by-phase, each step shipping green before the next. The spec's phase numbering is the order of work:

1. **Step 1** — Swift 6 flip + audit. Verify existing tests still pass.
2. **Step 2** — Foundation helpers (AtomicJSON, AtomicYAMLMarkdown, NexusPaths, Filesystem, Yams registered).
3. **Step 3** — All Codable types land + tests.
4. **Step 4** — Validation engine + tests.
5. **Step 5a** — `SpaceManager` + `TopicManager`/`Subtopic` flow + tests.
6. **Step 5b** — `VaultManager` + `ContentManager` + tests.
7. **Step 5c** — `AgendaManager` + `HomepageManager` + `TierConfigManager` + `SavedConfigManager` + tests.
8. **Step 6** — Sidebar UI replacement (Spaces section first → demoable; then Topics → demoable; then Vaults → demoable; remove all hardcoded placeholders last).
9. **Step 7** — All sheets + pickers + confirmations.
10. **Step 8** — Detail pane (`SidebarDetailView` + `VaultDetailView` + `CollectionDetailView` + `ContextDetailPlaceholder`).
11. **Step 9** — Item Window popover.
12. **Step 10** — `ContentView` wiring brings everything together.

If Step 1 surfaces > 30 min of Swift 6 friction, pause and report — fallback is to defer migration to v0.5 when GRDB lands and proceed on Swift 5.

#### Out of scope (explicitly)

- Tabs / tab strip / tab keyboard shortcuts (Framework v0.1b — deferred)
- Page Markdown editor (v0.6+) — Pages create / rename / delete only; clicking a Page in sidebar or Collection detail does nothing in this plan
- Composed-blocks rendering or editor for Spaces / Topics / Sub-topics / Homepage (v0.9)
- EventKit integration for Agenda (entitlement, usage descriptions, permissions, sync) — Agenda is data-layer scaffold only
- `tier1` / `tier2` / `tier3` relations property panel (Phase 7 of spec / v0.5)
- File watcher (FSEventStream) (v0.5)
- SQLite indexer (GRDB.swift) (v0.5)
- Settings scene (Tier-config editor, Saved-section labels editor, tagging-style picker) (v0.5)
- Saved-section content (Homepage / Calendar / Recents views) (v0.5)
- Calendar view over Agenda items (v0.4)
- Vault property-schema editor (v1.x)
- Vault view types beyond the basic detail Table (board / list / cards / gallery + view-config UI + saved per-Vault views) (v0.10)
- Move-strip rule for cross-Vault Page/Item moves (v0.3 hardening — out of paradigm scope)
- Full SF Symbol curated picker (small `TextField` only in this plan)
- Cross-nexus wikilink rewrite (v0.8)
- Wikilinks rendering at all (v0.8)
- Graph view foundation audit (Phase 11 of spec)

#### Verification (end-to-end)

After all steps:

1. `xcodebuild -project Pommora/Pommora.xcodeproj -scheme Pommora build` — zero warnings under Swift 6 strict concurrency.
2. All unit tests pass (~66 total: 26 existing + ~40 new).
3. Manual gold path (executed once with a fresh nexus):
   - `+ New Space` "Personal" / blue / `person.circle` → `<nexus>/.nexus/spaces/Personal.space.json` matches spec schema.
   - `+ New Topic` "Productivity" parented to Personal → `<nexus>/.nexus/topics/Productivity/_topic.json` + the folder exists.
   - `+ New Sub-topic` "GTD method" inside Productivity → `<nexus>/.nexus/topics/Productivity/GTD method.subtopic.json`.
   - Delete Productivity (promote default) → folder gone; "GTD method" is now a top-level Topic `<nexus>/.nexus/topics/GTD method/_topic.json` with parents inherited from Productivity.
   - `+ New Vault` "Planner" → `<nexus>/Planner/_vault.json` + the folder exists.
   - `+ New Collection` "Tasks" inside Planner → `<nexus>/Planner/Tasks/` folder.
   - `+ New Item` "Buy groceries" in Tasks → `<nexus>/Planner/Tasks/Buy groceries.json`. Click → Item Window opens; edit description; close; on-disk file reflects.
   - `+ New Page` "Notes" in Tasks → `<nexus>/Planner/Tasks/Notes.md` with frontmatter scaffold. Click → no-op (no editor yet).
   - Rename + delete works at every level; on-disk reflects every operation.
   - Topic delete with cascade option → all Sub-topics gone.
   - Homepage exists at `.nexus/homepage.json` on first launch even though no UI touched it.
   - Agenda schema exists at `Agenda/_agenda.json` (created on first AgendaManager init); no UI yet.
4. `codesign -d --entitlements - Pommora.app` — sandbox + user-selected-rw entitlements still present.
5. LLM-legibility check: `cat` any entity file → pretty-printed JSON (or YAML frontmatter for Pages) matches the locked schemas exactly.
6. Four-section sidebar visible: Saved (placeholder labels, no-op clicks), Spaces (live), Topics (live with chevron + sub-topics), Vaults (live with chevron + collections).
