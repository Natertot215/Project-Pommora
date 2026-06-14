### CRUD Patterns

SwiftUI patterns for per-entity CRUD UI — file format → sidebar UI → validation. Guideline, not enforcement.

---

#### Preview prerequisite — one shared primitive (`PagePreview`)

"Open in preview" is a generic affordance backed by **one shared primitive** — the `PagePreview` window (the `WindowGroup(id: "page-preview")` scene + `PageOpenRouter`; spec → `Features/Pages.md` § "Opening behavior") — not a per-feature one.

**Rule:** for any entity kind (Page, Page Type, Page Collection, Space, Topic, Project, Agenda Task, Agenda Event), preview support for that kind ships on the shared `PagePreview` primitive **before** any "open in preview" UI is wired for it. CRUD may land independently; the preview affordance waits. Half-wired feature-specific window plumbing (e.g. the v0.2.7.2 NavDropdown EntityWindowHost, since removed) rots when requirements shift — one project-wide primitive, bolt feature surfaces onto it. Today only Pages have preview support, routed per-vault via `open_in`.

---

#### Manager pattern — per entity, `@MainActor @Observable`

Every new entity (Space, Topic, Project, Page Type, Page Collection, Page, Agenda Task, Agenda Event, Homepage, Settings, …) gets its own `@MainActor @Observable final class` manager mirroring `NexusManager`'s shape. Per-entity (not one unified store) — narrows state-driven updates so changing a Topic doesn't re-evaluate the Spaces section.

```swift
@MainActor
@Observable
final class SpaceManager {
    private(set) var spaces: [Space] = []
    var pendingError: (any Error)?   // existential-any per project convention

    private let nexus: Nexus  // injected from NexusManager

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async { ... }
    @discardableResult
    func create(name: String, color: SpaceColor?, icon: String?) async throws -> Space { ... }
    func rename(_ space: Space, to newName: String) async throws { ... }
    func updateColor(_ space: Space, to color: SpaceColor?) async throws { ... }
    func delete(_ space: Space) async throws { ... }
}
```

Inject the active Nexus at construction; the init does NOT kick its own load — the parent view drives loading via `.onChange(of:initial:true)` on `NexusManager.currentNexus`, where `initial: true` covers the nil → Nexus transition. Keeping load out of init avoids racing the parent's `.onChange`.

**`pendingError` scope:** set from `loadAll`/`load` AND from every CRUD method (`create`, `rename`, `update*`, `delete`, reorder) — each catch block assigns `self.pendingError = error` before rethrowing out of `async throws`. A sidebar-level toast (`SidebarToast`) surfaces it transiently, so failed context-menu renames/deletes are no longer silent. Sheet-level forms (NewSpaceSheet etc.) additionally use per-view `@State errorMessage: String?` for inline display at the point of edit.

**Property schema mutation is shared, not per-manager (de-dup 2026-05-31).** The five property-schema methods — `addProperty` / `renameProperty` / `deleteProperty` / `reorderProperty` / `changeType` — are NOT reimplemented in each manager. They live in two shared `@MainActor` services: `PerTypeSchemaService` (PageType, keyed by `typeID`) and `SingletonSchemaService` (Agenda Task / Event, single `schema`). Each manager supplies a small per-side adapter (metadata URL, concrete error enum, member-file strip via `MemberFileStrip.forEach`, index `owningTypeKind`) and keeps its exact public signatures + concrete error enum + the `pendingError`-set-then-rethrow wrapper via a one-line delegator. Entity-level CRUD (create/rename/delete the Type or Collection itself) stays per-manager. 

---

#### Codable file types — `load(from:)` + `save(to:)` mirror `NexusIdentity`

Every Codable entity file follows `NexusIdentity`'s shape.

```swift
struct Space: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String          // ULID
    var tier: Int           // always 1; set in init, written as 1 via custom encode
    var title: String       // derived from filename on load, set on create
    var color: SpaceColor?  // nil = no color picked
    var icon: String?       // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date
}

extension Space {
    static func load(from url: URL) throws -> Space {
        try AtomicJSON.decode(Space.self, from: url)
    }
    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

---

#### Atomic JSON write — `Data.write(.atomic)` is enough

Reference pattern (from `NexusIdentity.save(to:)`):

```swift
enum AtomicJSON {
    static func encode<T: Codable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    static func decode<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    static func write<T: Codable>(_ value: T, to url: URL) throws {
        let data = try encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
```

`Data.write(to:options:[.atomic])` writes to a temp file + atomic rename under the hood — **no separate `.tmp` helper needed**. Reuse `AtomicJSON` for every Codable entity file. Output: pretty-printed + sorted keys + ISO-8601 dates — human-inspectable, agent-legible without app round-trip.

---

#### YAML frontmatter + body — `AtomicYAMLMarkdown` (preserving merge-on-write)

Yams (`github.com/jpsim/Yams`, MIT) backs the `AtomicYAMLMarkdown` codec — the single read/write path for Pages (`.md` frontmatter + body). No first-party Apple solution; `apple/swift-markdown` handles body but not frontmatter.

**Writes preserve foreign frontmatter by value — never cull.** A typed encode only emits the keys in `CodingKeys`; serializing that alone drops any plugin/foreign key an external tool wrote onto the file. So every full-frontmatter write merges the typed struct's keys back over the existing on-disk frontmatter rather than replacing it:

```swift
import Yams

// AtomicYAMLMarkdown.write(_:body:to:preservingFrom:modeledKeys:)
// 1. Encode the typed frontmatter (modeled keys only).
// 2. Read the existing file at `preservingFrom`; for each on-disk key:
//      modeled → substitute the typed value (or drop if the typed value cleared it);
//      foreign → pass through unchanged.
// 3. Append typed-only keys not already present; envelope with `---` fences + body.
```

- `modeledKeys = Set(CodingKeys.allCases.map(\.rawValue))` (`CaseIterable`) — the set the merge treats as Pommora-owned; everything else rides along.
- `preservingFrom:` is the URL the entity was read from (a rename renames old→new first, then saves to the new URL, so preservation reads the post-rename file).
- Yams round-trips by value — a foreign file's flow→block style reflows and comments/anchors drop on first re-serialization. Content is safe; exact styling is not.

This applies on every Page write path. Agenda (`.task.json` / `.event.json`) and sidecars stay JSON via `AtomicJSON`.

SPM: `https://github.com/jpsim/Yams.git` (pinned 5.4.0).

---

#### Sidebar pattern — extend existing `SidebarView`

`SidebarView` already uses `List` + `Section(isExpanded:)` + `DisclosureGroup` + the locked `SelectableRow` selection language. **No new sidebar architecture needed** — swap placeholders for real data from each manager as it lands.

Each `xxxSection` is its own `struct: View` (not a computed property) so SwiftUI can skip body re-evaluation when inputs don't change — pattern from `swiftui-expert-skill/references/view-structure.md` ("Extract Subviews, Not Computed Properties").

Creation triggers use the stub-and-inline-rename coordinator (`CRUD/CreateWithInlineEdit.swift` + `CRUD/DefaultTitleResolver.swift`) — there is no `SidebarSheet` enum and no `.sheet(item:)` switch. Each manager's `create*` returns the new entity via `@discardableResult`; the coordinator flips the matching row into rename mode via shared `editingID` + `justCreatedID` bindings owned by `ContentView`.

---

#### Folder + file atomicity (multi-step filesystem ops)

Creating a Topic / Vault is **two steps** — (1) create folder, (2) write metadata file. `Data.write(.atomic)` only atomicizes step 2; the combined op needs **best-effort rollback** on failure + **idempotent recovery** on load.

```swift
func create(name: String, parents: [String]) async throws {
    let folderURL = NexusPaths.topicsDir(in: nexus)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    do {
        let topic = Topic(id: ULID.generate(), title: name, parents: parents, ...)
        let metaURL = folderURL.appendingPathComponent("_topic.json")
        try AtomicJSON.write(topic, to: metaURL)
    } catch {
        try? FileManager.default.removeItem(at: folderURL)  // rollback orphan
        throw error
    }
}
```

**Idempotent recovery on load:** if `loadAll()` encounters a folder under `.nexus/topics/` without a `_topic.json` inside, skip silently — treat as user-manual organization; user repairs via Finder. **Folder rename** uses `FileManager.moveItem(at:to:)` — atomic on same volume (always true for nexus contents).

##### Rename atomicity — rename-first-then-write-metadata, rollback on failure

Renames that touch two filesystem ops (folder/file rename + metadata save) follow one uniform pattern across every `rename*` site: **rename the folder/file first → write metadata → if the metadata write fails, roll the rename back → if the rollback ALSO fails, throw `RenameAtomicityError`** (`AtomicIO/RenameAtomicityError.swift`, a `LocalizedError` carrying both the save error and the revert error). The managers set `pendingError` on the unrecoverable case before rethrowing. Same shape in `SpaceManager.rename`, `TopicManager.renameTopic` + `renameProject` + `moveProject`, `PageTypeManager.renamePageType` + `renamePageCollection`, `PageContentManager.renamePage`, `AgendaTaskManager.renameTask`, `AgendaEventManager.renameEvent`. The remaining gap is the rare double-failure (both rename and rollback fail) — surfaced to the user via `RenameAtomicityError` rather than silently leaving divergent on-disk state.

##### Cover + banner assets — copy-then-write, delete-AFTER-write

Page `cover` and container `banner` are the same asset-CRUD shape — a nexus-relative path string on the entity (`cover` on Page frontmatter; `banner` on the `_pagetype.json` / `_pagecollection.json` sidecar). The image lives at `.nexus//assets//<entityID>//<file>`; both flows share `CoverAssetStore` (collision-safe naming via `-2` / `-3` suffixes + a 500 MB hard-cap size guard) and `AssetURLResolver` for path→URL (DRY).

- **Container banner CRUD routes through `PageTypeManager.setBanner(_:forContainer:)`** (handles both container kinds; Task-3 fresh read-modify-write of the sidecar, no SQLite upsert — `banner` isn't indexed). Page covers persist via `PageContentManager.updatePageFrontmatter`.
- **Set / Change — copy first, then write the field.** `CoverAssetStore.storeSync` copies the source into the entity's asset folder **inside the security-scoped window** (the synchronous copy completes before the `defer` closes the scope; only the field-persist hops to a `Task`). The returned relative path is written to `cover` / `banner` only after the copy succeeds.
- **Delete-AFTER-write discipline.** On Change or Remove, the new path (or `nil`) is written FIRST, and `CoverAssetStore.delete` removes the previously-referenced asset **only after that write succeeds** — so a failed write never leaves the field pointing at a deleted file, and never orphans the old file before the new one commits. `delete` is containment-guarded (only removes files under the entity's own `assetsDir`) and no-ops on nil/missing.
- **UI mirror.** `ContainerBannerView` shows a hover-revealed "Add Banner" affordance in the empty state and a Change / Remove context menu when set — mirroring the page-level cover Set / Change / Remove flow (`CoverPicker`). Copy failures surface via the manager's `pendingError` → `SidebarToast`.

---

#### Validation — pure functions per entity

Enforced at the manager layer, before write.

```swift
enum SpaceValidator {
    enum ValidationError: Error {
        case emptyTitle
        case invalidTitleCharacters
        case duplicateTitle
    }

    static func validate(title: String, existing: [Space], excluding: Space? = nil) throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        let invalidChars: Set<Character> = ["/", ":", "\\"]
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            // Check `trimmed`, not `title` — matches the empty-check above
            throw ValidationError.invalidTitleCharacters
        }
        let conflicts = existing.contains {
            $0.title.lowercased() == trimmed.lowercased() && $0.id != (excluding?.id ?? "")
        }
        guard !conflicts else { throw ValidationError.duplicateTitle }
    }
}
```

Tier-parent validation needs cross-entity lookup (Project's parent Topic ID must resolve). **Locked Swift 6 pattern:** managers take a `contextProvider: @MainActor @escaping () -> NexusContext` closure at init returning a fresh snapshot per call. NexusContext's inner closures are `@Sendable` (cross into off-actor validators); capture `Sendable` value-type arrays into local lets at the outer `@MainActor` scope:

```swift
@MainActor @Observable
final class NexusEnvironment {            // owns + constructs every per-Nexus manager; injected once via .injectNexusEnvironment(_:)
    init(nexus: Nexus, nexusManager: NexusManager) {
        let spaceMgr = SpaceManager(nexus: nexus)
        let topicMgr = TopicManager(nexus: nexus) { @MainActor in
            // Snapshot live state into Sendable locals; inner closures capture the snapshot
            let spaces = spaceMgr.spaces
            let topics = topicMgr.topics
            let projects = topicMgr.projectsByParent
            return NexusContext(
                lookupSpace: { id in spaces.first { $0.id == id } },
                lookupTopic: { id in topics.first { $0.id == id } },
                lookupProject: { id in projects.values.lazy.flatMap { $0 }.first { $0.id == id } },
                lookupVault: { id in /* via pageTypeMgr — similar snapshot */ nil }
            )
        }
    }
}
```

**One-shot only:** invoked per-validate-call and thrown away. **Do not store** in a long-lived closure (background indexer, search index, etc.) — snapshot would go stale. A higher-level `NexusCoordinator` aggregating all managers is post-v1; v1 uses the per-manager `contextProvider` closure pattern.

---

#### Sandbox + security-scoped access — already solved

`NexusManager` handles `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` lifecycle. New file writes inside the nexus inherit access from the active scope — **no per-write bookmark needed**.

**Discipline:** new entity managers must NOT call `startAccessing` independently — they assume `NexusManager` holds the active scope and read `nexusURL` from the active `Nexus`, writing within that tree.

EventKit (Agenda, Phase 6.5): separate sandbox entitlement (`com.apple.security.personal-information.calendars`) + Info.plist usage description keys + `requestFullAccessTo*` APIs — its own access flow, NOT the file-r/w resource scope. Detail → `Features/Agenda.md`.

---

#### SF Symbol picker — Pommora-native `IconPicker`

Pommora's own `IconPicker` (`Properties/IconPicker/`) is the icon chooser everywhere — a compact (260×306) Liquid-Glass dropdown over the full SF Symbols catalog (`IconCatalog`, bundled as source) with search + Saved/favorites (`IconFavorites`, app-level UserDefaults). It replaced the `xnth97/SymbolPicker` SPM dep (2026-05-30, paradigm decision #3), which hardcoded a 540pt macOS frame and kept its catalog `internal` — neither resizable nor re-skinnable.

**Present it via the one DRY modifier**, anchored to the icon button. `.presentationBackground(.clear)` (baked into the modifier) strips the system popover's own material so only the picker's own `chipDropdownPanel` glass shows — no double-glass:

```swift
Button { iconPickerOpen = true } label: {
    Image(systemName: icon).fieldBackground()
}
.iconPickerPopover(isPresented: $iconPickerOpen, symbol: iconBinding)
```

`iconBinding` is a `Binding<String?>` whose setter commits the pick; nil clears it (the picker's "Remove Icon" row, shown only when an icon is set). The picker writes the binding and dismisses on pick.

**Edit-Icon on existing rows** routes through `IconPickerSheet`, which hosts `IconPicker` and dispatches the chosen symbol to the right manager's `updateXIcon` via the `SidebarSheet.IconTarget` switch (`.space` | `.topic` | `.project` | `.pageType` | `.pageCollection` | `.page`). **Its `@Environment` managers must be reachable wherever it's presented** — a `.sheet` inherits the host's environment, so every NavigationSplitView column that can present it must inject every manager it reads (quirk #15; a `TopicManager` missing from the detail-column chain crashed the detail-table Edit Icon).

**Create flows** use `IconPickerField` — a button-field that holds the pick in local `@State` until Save, presenting `IconPicker` through the same `.iconPickerPopover`.

---

#### Inline editing principle — managers own writes, embeds dispatch to managers

Every embedded view (Context page, Homepage) is **a live, fully-editable view of its source** — not a snapshot.

- Block stores the **reference** (source entity ID + view config + filters), not a snapshot
- Edits route through the source entity's manager (e.g. checking off a Task in an embed calls `AgendaTaskManager.toggleCompleted(...)`)
- Manager atomically writes the source file
- File watcher catches the change → SQLite re-indexes → all embedded views refresh live

**No separate "embed-edit path" vs "primary-surface edit path."** Same manager, same methods. One source of truth per entity. Detail → `Features/Domain-Model.md → Inline editing principle`.

---

#### Inline property editing + picker hosting

How a window / panel / detail surface hosts editable relation, status, and tier values. The reusable units (Task 6) let any future surface wire property editing by recipe instead of reinventing it.

- **`PropertyEditorRow`** is the per-property editor row. Hosts pass `definition` + a `@Binding value`, plus (for context links) `index: PommoraIndex?` + `relationDisplay: ContextDisplayResolver?` (both defaulted `nil`, so non-relation call sites compile unchanged). It renders the right editor per `PropertyType`: relation → `ContextValueEditor`, status → `ChipDropdown(.single)`.
- **`ContextValueEditor`** is the inline context-link/tier editor: shows the current value as `ContextChip` icon+title (or an "Add" affordance) and presents the grouped `ContextPicker` in a **chromeless popover** on tap (`.presentationBackground(.clear)`). The picker owns its own **fixed frame**, so the chromeless popover can't collapse — never rely on the popover to size it (the `9deb818` rule). Tiers reuse it directly with `scope: .contextTier(n)`.
- **Value-commit contract — the host owns persistence.** `ContextValueEditor` writes the new `[ID]` array back through its `@Binding`; the host's setter routes to its manager (`PageContentManager.updatePageFrontmatter` / `updatePageProperty`, or a VM's `handleTierChange` → debounced `onSave`). The editor never knows the manager — binding-in, binding-out.
- **Env (quirk #16).** The editor needs `index` (picker candidate query) + `ContextDisplayResolver` (current-value chips). Pass them **explicitly as params** when the host is a sheet/popover — sheet env-inheritance is the classic SIGTRAP trap; read via `@Environment` only when the host sits directly in the `.detail` chain that injects them.
- **Current hosts:** `FrontmatterInspector`, mounted on both surfaces — the main-pane Page editor (full scale) and the PagePreview window (`compact: true`) — editable tiers + relation/status properties, persisting via `updatePageFrontmatter` through the shared `FrontmatterInspectorViewModel` path.

---

#### Modern SwiftUI API hygiene

Per `swiftui-expert-skill/references/latest-apis.md`:

- `@Observable` + `@State` for view-owned managers (not `@StateObject`)
- `@Bindable` for injected `@Observable` objects needing bindings
- `.foregroundStyle(_:)` not `.foregroundColor()`
- `.clipShape(.rect(cornerRadius:))` not `.cornerRadius()`
- `.alert(_:isPresented:actions:message:)` not `alert(isPresented:content:)`
- `.confirmationDialog(...)` not `actionSheet(...)`
- `.onChange(of:) { }` or `.onChange(of:) { old, new in }` — not `onChange(of:perform:)`
- `Button` for tappable elements, not `onTapGesture`
- `NavigationStack` / `NavigationSplitView`, not `NavigationView`
- `tint(_:)` not `accentColor(_:)`
- `@Entry` macro for custom environment values, not manual `EnvironmentKey`

Target macOS 26.4 — no back-deployment burden.
