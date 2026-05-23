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
    var spaces: [Space] = []
    var pendingError: (any Error)?   // existential-any per project convention

    private let nexus: Nexus  // injected from NexusManager

    init(nexus: Nexus) {
        self.nexus = nexus
        Task { await loadAll() }
    }

    func loadAll() async { ... }
    func create(name: String, color: SpaceColor, icon: String?) async throws { ... }
    func rename(_ space: Space, to newName: String) async throws { ... }
    func updateColor(_ space: Space, to color: SpaceColor) async throws { ... }
    func delete(_ space: Space) async throws { ... }
}
```

Inject the active Nexus's root URL at construction; re-load when `NexusManager.currentNexus` changes via `.onChange(of:initial:true)` on the parent view — `initial: true` covers the nil → Nexus transition, else first construction races a separate `.task { await loadOnLaunch() }`.

**`pendingError` scope (v0.2):** assigned only from `loadAll`/`load`; CRUD methods (`create`, `rename`, `update*`, `delete`) throw out of `async throws` and the row/sheet catch block surfaces. Failed sidebar context-menu renames/deletes are currently silent. Locked direction (4-commit pre-merge cleanup): managers ALSO set `pendingError` on CRUD failures + a sidebar-level toast surfaces it transiently. Until then, sheet-level forms (NewSpaceSheet etc.) use per-view `@State errorMessage: String?` for inline display.

---

#### Codable file types — `load(from:)` + `save(to:)` mirror `NexusIdentity`

Every Codable entity file follows `NexusIdentity`'s shape.

```swift
struct Space: Codable, Equatable, Identifiable, Hashable {
    var id: String          // ULID
    var tier: Int = 1
    var title: String       // derived from filename on load, set on create
    var color: SpaceColor
    var icon: String?       // SF Symbol name
    var blocks: [SpaceBlock]
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

```swift
struct SidebarView: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var presentedSheet: SidebarSheet?

    var body: some View {
        List {
            pinnedSection
            spacesSection
            topicsSection
            itemsSection      // Items above Pages — quicker-capture entities ride higher
            pagesSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace:                          NewSpaceSheet()
            case .newTopic:                          NewTopicSheet()
            case .newProject(let topic):             NewProjectSheet(topic: topic)
            case .newPageType:                       NewPageTypeSheet()
            case .newPageCollection(let type):       NewPageCollectionSheet(type: type)
            case .newPage(let coll, let type):       NewPageSheet(collection: coll, type: type)
            case .newItemType:                       NewItemTypeSheet()        // stub in v0.3.0
            case .newItemCollection(let type):       NewItemCollectionSheet(type: type) // stub
            case .newItem(let coll, let type):       NewItemSheet(collection: coll, type: type)
            // No Agenda sheets — Agenda has no sidebar entry; Calendar plan adds its own.
            }
        }
    }
}
```

Each `xxxSection` is its own `struct: View` (not a computed property) so SwiftUI can skip body re-evaluation when inputs don't change — pattern from `swiftui-expert-skill/references/view-structure.md` ("Extract Subviews, Not Computed Properties").

---

#### Creation sheets — enum-keyed `.sheet(item:)`, triggered by right-click context menus

Single sheet modifier with an `Identifiable` enum, not N boolean state properties. **Triggered by `.contextMenu` on rows / section areas, NOT by always-visible "+ New" buttons** (paradigm decision 2026-05-17 — see `Sidebar.md` for the full right-click table).

```swift
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newProject(parent: Topic)
    case newPageType
    case newPageCollection(type: PageType)
    case newPage(collection: PageCollection?, type: PageType)
    case newItemType
    case newItemCollection(type: ItemType)
    case newItem(collection: ItemCollection?, type: ItemType)
    // No `newAgendaTask` / `newAgendaEvent` — Agenda has no sidebar entry;
    // Calendar plan adds its own sheet enum when it builds Agenda UI.
    case editTopicParents(Topic)
    case editIcon(IconTarget)
    case editColor(Space)

    enum IconTarget: Hashable {
        case space(Space), topic(Topic), project(Project),
             pageType(PageType), pageCollection(PageCollection),
             itemType(ItemType), itemCollection(ItemCollection)
    }

    var id: String {
        switch self {
        case .newSpace:                       "newSpace"
        case .newTopic:                       "newTopic"
        case .newProject(let t):              "newProject-\(t.id)"
        case .newPageType:                    "newPageType"
        case .newPageCollection(let t):       "newPageCollection-\(t.id)"
        case .newPage(let c, let t):          "newPage-\(c?.id ?? t.id)"
        case .newItemType:                    "newItemType"
        case .newItemCollection(let t):       "newItemCollection-\(t.id)"
        case .newItem(let c, let t):          "newItem-\(c?.id ?? t.id)"
        case .editTopicParents(let t):        "editTopicParents-\(t.id)"
        case .editIcon(let t):                "editIcon-\(t)"  // expanded form
        case .editColor(let s):               "editColor-\(s.id)"
        }
    }
}
```

Each sheet owns its actions via `@Environment(\.dismiss)` — no callback prop-drilling. Each case carries the parent entity binding so the sheet never re-asks for parent location. Post-ParadigmV2: `PageCollection` and `ItemCollection` are **bare-unambiguous** Swift type names — no `Pommora.X` qualification needed. The pre-ParadigmV2 quirk #6 (`Pommora.Collection`) is RETIRED.

The sheet titles displayed to the user read from `SettingsManager` so user-renamed labels surface: "New Vault" (Page Type, Pages-side default) / "New Collection" (Page Collection) / "New Type" (Item Type, Items-side default) / "New Set" (Item Collection). Items-side sheets ship as minimal `ContentUnavailableView` stubs at v0.3.0; designed UI lands in a follow-up plan.

---

#### Inline rename — `@FocusState` + conditional `TextField`

```swift
struct SpaceRow: View {
    let space: Space
    @Binding var editingID: String?
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if editingID == space.id {
            TextField("", text: $draft)
                .focused($isFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) { cancel(); return .handled }
                .onAppear { draft = space.title; isFocused = true }
        } else {
            SelectableRow(title: space.title, ...)
                .contextMenu {
                    Button("Rename") { editingID = space.id }
                    Button("Delete", role: .destructive) { ... }
                }
        }
    }
    private func commit() { ... }
    private func cancel() { editingID = nil }
}
```

Trigger rename via right-click → Rename, keyboard Enter on selected row, or (power users only) double-click — avoid double-click as default for openable entities (conflicts with open-on-click). **Esc-to-cancel:** prefer `.onKeyPress(.escape)` over the legacy macOS-only `.onExitCommand` — forward-compatible API.

---

#### Right-click context menu — `.contextMenu`

Native SwiftUI `.contextMenu` on each row. Color/icon pickers + delete confirmation drive via `.sheet(item:)` and `.confirmationDialog(item:)`.

```swift
SelectableRow(...)
    .contextMenu {
        Button("Rename") { startRename(space) }
        Button("Change Color") { presentedSheet = .colorPicker(space) }
        Button("Change Icon") { presentedSheet = .iconPicker(space) }
        Divider()
        Button("Delete", role: .destructive) { confirmDelete = space }
    }
```

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

##### Rename atomicity — pending consistent pattern (4-commit cleanup)

v0.2 managers use **rename-folder-first-then-write-metadata** with an unrecoverable failure mode: if metadata write fails the folder is already at the new name with stale `modified_at`. Post-ParadigmV2 rename sites (one per manager): `SpaceManager.rename`, `TopicManager.renameTopic` + `renameProject` + `moveProject`, `PageTypeManager.renamePageType`, `PageTypeManager.renamePageCollection`, `ItemTypeManager.renameItemType`, `ItemTypeManager.renameItemCollection`, `PageContentManager.renamePage`, `ItemContentManager.renameItem`, `AgendaTaskManager.renameTask`, `AgendaEventManager.renameEvent`.

Locked direction (4-commit pre-merge cleanup): pick ONE pattern. Candidates:

1. **Write metadata first, then rename folder** — on folder-rename failure metadata is already correct; retry rename on next load. Resilient; brief on-disk name divergence.
2. **Rollback on metadata failure** — current pattern; rename folder back on metadata-write failure. Risk: rename-back can also fail.
3. **Write-temp + atomic rename of metadata, then folder rename** — closest to true atomicity; requires two-phase recovery.

Decision locked when cleanup executes; canonical flow documented here then.

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
    let target: SidebarSheet.IconTarget   // .space | .topic | .project | .pageType | .pageCollection | .itemType | .itemCollection
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var icon: String = ""

    var body: some View {
        SymbolPicker(symbol: $icon)  // nullable variant exposes a delete-icon button
            .onAppear { icon = currentIcon ?? "" }
            .onChange(of: icon) { _, newValue in
                Task { await save(newIcon: newValue.isEmpty ? nil : newValue); dismiss() }
            }
    }
    // currentIcon + save() switch on `target` to dispatch to the right manager method
}
```

SymbolPicker auto-renders Cancel / clear / done chrome. Wrapper's only job: bind the picked symbol to the right manager's `updateIcon` via the `IconTarget` enum. SPM dep added at commit `22e3fc6`, resolver 1.6.2. No curated default list — library's full search picker is the only icon-picker UI in v0.2.

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
