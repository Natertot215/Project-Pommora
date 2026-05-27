### CRUD Patterns

SwiftUI patterns for per-entity CRUD UI — file format → sidebar UI → validation. Guideline, not enforcement.

---

#### Preview-window prerequisite (locked v0.2.7.1)

"Open in preview" is a generic affordance (dropdown preview-on-click, future `⌥⌘O`, future Cmd-click-from-anywhere) backed by a **shared primitive** (PreviewWindow), not a per-feature one.

**Rule:** for any entity kind (Page, Page Type, Page Collection, Item Type, Item Collection, Space, Topic, Project, Item, Agenda Task, Agenda Event), PreviewWindow support for that kind ships **before** any "open in preview" UI is wired. CRUD may land independently; the standalone-window affordance waits. Half-wired feature-specific window plumbing (e.g. the v0.2.7.2 NavDropdown EntityWindowHost, since removed) rots when requirements shift — one project-wide primitive, bolt feature surfaces onto it. Practical implication: new entity CRUD lands without standalone-window affordances by default; double-click and Cmd-click-from-sidebar route to the main detail pane until PreviewWindow gains support. Exception: ItemWindow predates this rule, so Item rows route to ItemWindow today; may migrate to PreviewWindow per future spec.

---

#### Manager pattern — per entity, `@MainActor @Observable`

Every new entity (Space, Topic, Project, Page Type, Page Collection, Page, Item Type, Item Collection, Item, Agenda Task, Agenda Event, Homepage, Settings, …) gets its own `@MainActor @Observable final class` manager mirroring `NexusManager`'s shape. Per-entity (not one unified store) — narrows state-driven updates so changing a Topic doesn't re-evaluate the Spaces section. Post-ParadigmV2: `ContentManager` splits into `PageContentManager` (Pages side) + `ItemContentManager` (Items side); `AgendaManager` splits into `AgendaTaskManager` + `AgendaEventManager`.

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

#### YAML frontmatter — use Yams

Yams (`github.com/jpsim/Yams`, MIT) — Page frontmatter parsing. No first-party Apple solution; `apple/swift-markdown` handles body but not frontmatter.

```swift
import Yams

struct PageFile {
    var frontmatter: PageFrontmatter
    var body: String

    static func load(from url: URL) throws -> PageFile {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fm, body) = try splitFrontmatter(raw)
        let frontmatter = try YAMLDecoder().decode(PageFrontmatter.self, from: fm)
        return PageFile(frontmatter: frontmatter, body: body)
    }

    func save(to url: URL) throws {
        let fm = try YAMLEncoder().encode(frontmatter)
        let raw = "---\n\(fm)---\n\n\(body)"
        try raw.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

SPM: `https://github.com/jpsim/Yams.git`, `from: "5.1.0"`. Add at Phase 0 so Phase 6 (Page CRUD) doesn't block on dependency management.

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

Renames that touch two filesystem ops (folder/file rename + metadata save) follow one uniform pattern across every `rename*` site: **rename the folder/file first → write metadata → if the metadata write fails, roll the rename back → if the rollback ALSO fails, throw `RenameAtomicityError`** (`AtomicIO/RenameAtomicityError.swift`, a `LocalizedError` carrying both the save error and the revert error). The managers set `pendingError` on the unrecoverable case before rethrowing. Same shape in `SpaceManager.rename`, `TopicManager.renameTopic` + `renameProject` + `moveProject`, `PageTypeManager.renamePageType` + `renamePageCollection`, `ItemTypeManager.renameItemType` + `renameItemCollection`, `PageContentManager.renamePage`, `ItemContentManager.renameItem`, `AgendaTaskManager.renameTask`, `AgendaEventManager.renameEvent`. The remaining gap is the rare double-failure (both rename and rollback fail) — surfaced to the user via `RenameAtomicityError` rather than silently leaving divergent on-disk state.

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
@MainActor
final class ContentView {
    private func constructManagers(for nexus: Nexus) {
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
                lookupPageType: { id in /* via pageTypeMgr — similar snapshot */ nil },
                lookupItemType: { id in /* via itemTypeMgr — similar snapshot */ nil }
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

#### SF Symbol picker — `xnth97/SymbolPicker` SPM dep behind `IconPickerSheet` wrapper

Paradigm decision 2026-05-16 (see `// Guidelines//Paradigm-Decisions.md`): use `xnth97/SymbolPicker` wrapped behind Pommora's own `IconPickerSheet`. Wrapping isolates call sites from the third-party API — swapping libraries is a single-file rewrite in the wrapper.

```swift
import SymbolPicker

struct IconPickerSheet: View {
    let target: SidebarSheet.IconTarget   // .space | .topic | .project | .pageType | .itemType
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var icon: String? = nil  // nullable so the picker shows its delete-icon button

    var body: some View {
        SymbolPicker(symbol: $icon)
            .onAppear { /* initialize from currentIcon, guard one-shot */ }
            .onChange(of: icon, initial: false) { _, newValue in
                Task { await save(newIcon: newValue) }  // nil clears back to default
            }
    }
    // currentIcon + save() switch on `target` to dispatch to the right manager method
}
```

SymbolPicker renders its own chrome (search field, x-close, symbol grid, and a delete button when the binding is nullable) and auto-dismisses on pick / delete / close — the wrapper adds no Cancel/Save of its own. Its only job: bind the picked symbol to the right manager's `updateIcon` via the `IconTarget` enum. Collections aren't icon-pickable, so `IconTarget` has no `.pageCollection` / `.itemCollection` case. SPM dep added at commit `22e3fc6`, resolver 1.6.2. No curated default list — the library's full search picker is the only icon-picker UI.

---

#### Inline editing principle — managers own writes, embeds dispatch to managers

Every embedded view (Context page, Homepage) is **a live, fully-editable view of its source** — not a snapshot.

- Block stores the **reference** (source entity ID + view config + filters), not a snapshot
- Edits route through the source entity's manager (e.g. checking off a Task in an embed calls `AgendaTaskManager.toggleCompleted(...)`)
- Manager atomically writes the source file
- File watcher catches the change → SQLite re-indexes → all embedded views refresh live

**No separate "embed-edit path" vs "primary-surface edit path."** Same manager, same methods. One source of truth per entity. Detail → `Features/Domain-Model.md → Inline editing principle`.

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
