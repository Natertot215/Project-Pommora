### CRUD Patterns

SwiftUI patterns for per-entity CRUD UI in Pommora — what every new entity manager should look like, from file format through sidebar UI through validation. Derived from the existing `NexusManager` / `NexusIdentity` / `NexusStore` shape (v0.1a) and the swiftui-expert-skill research captured during the RC-session domain-model revision.

This is a Guideline — patterns to follow, not enforcement. Full per-entity CRUD scope lives at `// Planning//Contexts-Vaults-spec.md`.

---

#### Manager pattern — per entity, `@MainActor @Observable`

Every new entity (Space, Topic, Sub-topic, Vault, Item, Page, Agenda item, Homepage, …) gets its own `@MainActor @Observable final class` manager mirroring `NexusManager`'s shape. Per-entity managers (not one unified store) — keeps state-driven updates narrowly scoped so changing a Topic doesn't re-evaluate the Spaces section.

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

Inject the active Nexus's root URL into each manager at construction; managers re-load when `NexusManager.currentNexus` changes (via `.onChange(of:initial:true)` on the parent view — `initial: true` covers the initial nil → Nexus transition; without it, the first construction relies on a separate `.task { await loadOnLaunch() }` race).

**`pendingError` scope (v0.2 state):** today, managers assign `pendingError` only from `loadAll`/`load` paths — CRUD methods (`create`, `rename`, `update*`, `delete`) throw out of `async throws` and the row/sheet catch block is responsible for surfacing. This means failed renames / deletes from sidebar context-menu actions are currently silent (the row's catch block has no error UI). The locked direction (4-commit pre-merge cleanup, paradigm-scaffolding branch) is: managers ALSO set `pendingError` on CRUD failures, and a sidebar-level toast observes the error and surfaces it transiently. Until that lands, sheet-level forms (NewSpaceSheet etc.) use per-view `@State errorMessage: String?` for inline error display.

---

#### Codable file types — `load(from:)` + `save(to:)` mirror `NexusIdentity`

Every Codable entity file follows `NexusIdentity`'s shape:

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

Pommora's existing `NexusIdentity.save(to:)` pattern is the atomic-write reference:

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

`Data.write(to:options:[.atomic])` writes to a temp file + atomic rename under the hood — **no separate `.tmp` helper needed**. Reuse `AtomicJSON` for every Codable entity file.

JSON output: pretty-printed + sorted keys + ISO-8601 dates. Human-inspectable on disk; agent-legible without app round-trip.

---

#### YAML frontmatter — use Yams

Yams (`github.com/jpsim/Yams`, MIT) is the recommended dependency for Page frontmatter parsing. No first-party Apple solution; `apple/swift-markdown` handles Markdown body but not frontmatter.

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

Add via Swift Package Manager: `https://github.com/jpsim/Yams.git`, version `from: "5.1.0"`. Worth adding at Phase 0 even though Spaces don't need it — Phase 6 (Page CRUD) shouldn't block on dependency management.

---

#### Sidebar pattern — extend existing `SidebarView`

The current `SidebarView` already uses `List` + `Section(isExpanded:)` + `DisclosureGroup` + the locked `SelectableRow` selection language. **No new sidebar architecture needed** — swap placeholders for real data from each manager as it lands.

```swift
struct SidebarView: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager

    @State private var presentedSheet: SidebarSheet?

    var body: some View {
        List {
            savedSection
            spacesSection
            topicsSection
            vaultsSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace:                  NewSpaceSheet()
            case .newTopic:                  NewTopicSheet()
            case .newVault:                  NewVaultSheet()
            case .newCollection(let vault):  NewCollectionSheet(vault: vault)
            case .newSubtopic(let topic):    NewSubtopicSheet(topic: topic)
            }
        }
    }

    // Each `xxxSection` extracted to its own SwiftUI `View` struct (not a computed
    // var) so SwiftUI can skip body re-evaluation when its inputs don't change.
}
```

Section structs are extracted as their own `struct: View` types, not computed properties — extracted-as-struct pattern from `swiftui-expert-skill/references/view-structure.md` ("Extract Subviews, Not Computed Properties").

---

#### Creation sheets — enum-keyed `.sheet(item:)`, triggered by right-click context menus

Single sheet modifier with an `Identifiable` enum, not N boolean state properties. **Triggered by `.contextMenu` items on rows / section areas, NOT by always-visible "+ New" buttons** (paradigm decision 2026-05-17 — see `Sidebar.md` for the full right-click table).

```swift
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newSubtopic(parent: Topic)
    case newVault
    case newCollection(vault: Vault)
    case newPage(collection: Pommora.Collection, vault: Vault)
    case newItem(collection: Pommora.Collection, vault: Vault)
    case editTopicParents(Topic)
    case editIcon(IconTarget)
    case editColor(Space)

    enum IconTarget: Hashable {
        case space(Space), topic(Topic), subtopic(Subtopic), vault(Vault)
    }

    var id: String {
        switch self {
        case .newSpace:                       "newSpace"
        case .newTopic:                       "newTopic"
        case .newSubtopic(let t):             "newSubtopic-\(t.id)"
        case .newVault:                       "newVault"
        case .newCollection(let v):           "newCollection-\(v.id)"
        case .newPage(let c, _):              "newPage-\(c.id)"
        case .newItem(let c, _):              "newItem-\(c.id)"
        case .editTopicParents(let t):        "editTopicParents-\(t.id)"
        case .editIcon(let t):                "editIcon-\(t)"  // expanded form
        case .editColor(let s):               "editColor-\(s.id)"
        }
    }
}
```

Each sheet owns its actions via `@Environment(\.dismiss)` — no callback prop-drilling. Each enum case carries the parent entity binding through so the sheet never re-asks for parent location — the right-click cursor already identified it.

**`Pommora.Collection` qualification** required on enum case associated values that carry `Collection` — the bare name shadows with `Swift.Collection` protocol. See project quirk #6 in `// CLAUDE.md`.

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
                .onKeyPress(.escape) { cancel(); return .handled }   // Esc cancels (iOS 17+/macOS 14+)
                .onAppear {
                    draft = space.title
                    isFocused = true
                }
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

Trigger rename via right-click → Rename, keyboard Enter on selected row, or — for power users only — double-click on the row. Avoid double-click as the default trigger for openable entities (it conflicts with open-on-click).

**Esc-to-cancel:** prefer `.onKeyPress(.escape)` (iOS 17+ / macOS 14+ — Pommora targets macOS 26.4 so always available). The legacy `.onExitCommand` is macOS-only and still works but `.onKeyPress` is the forward-compatible API.

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

Creating a Topic / Vault is **two steps** — (1) create folder, (2) write metadata file. `Data.write(.atomic)` only atomicizes the second step; the combined operation needs **best-effort rollback** on failure plus **idempotent recovery** on load.

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

**Idempotent recovery on load:** if `loadAll()` encounters a folder under `.nexus/topics/` without a `_topic.json` inside, skip it silently — treat as cosmetic / user-manual organization rather than crash or auto-create a phantom Topic. User can repair via Finder.

**Folder rename** uses `FileManager.moveItem(at:to:)` — atomic on same volume (always true for nexus contents; cross-volume is impossible since the whole nexus is one path tree).

##### Rename atomicity — pending consistent pattern (4-commit cleanup)

The v0.2 managers all use a **rename-folder-first-then-write-metadata** pattern that has an unrecoverable failure mode: if the metadata write fails (disk full, permissions, etc.) the folder is already at the new name with stale `modified_at`. Six sites today:

- `SpaceManager.rename`
- `TopicManager.renameTopic`
- `TopicManager.renameSubtopic` + `moveSubtopic`
- `VaultManager.renameVault`
- `VaultManager.renameCollection`
- `ContentManager.renameItem`

The locked direction (4-commit pre-merge cleanup) is to pick ONE pattern and apply consistently. Three candidates:

1. **Write metadata first, then rename folder** — if folder rename fails, the metadata write has already succeeded with the new title, so we attempt the rename again on next load. Resilient but the metadata-vs-folder name divergence is briefly observable on disk.
2. **Rollback on metadata failure** — current pattern; on metadata-write failure, attempt to rename the folder back. Risk: rename-back could also fail.
3. **Write-temp + atomic rename of metadata, then folder rename** — closest to true atomicity but requires two-phase recovery on failure.

Decision will be locked when the 4-commit cleanup executes. Pattern will then be documented here as the canonical rename flow.

---

#### Validation — pure functions per entity

Validation enforced at the manager layer, before write:

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
            // Check `trimmed`, not `title` — consistent with the empty-check pattern above
            throw ValidationError.invalidTitleCharacters
        }
        let conflicts = existing.contains {
            $0.title.lowercased() == trimmed.lowercased() && $0.id != (excluding?.id ?? "")
        }
        guard !conflicts else { throw ValidationError.duplicateTitle }
    }
}
```

Tier-parent validation needs cross-entity lookup (a Sub-topic's parent Topic ID must resolve to an actual Topic). **The locked Swift 6 pattern**: managers take a `contextProvider: @MainActor @escaping () -> NexusContext` closure at init that returns a fresh snapshot per call. NexusContext's own inner closures are `@Sendable` (they cross into validators that may run off-actor), so capture `Sendable` value-type arrays (`spaceMgr.spaces`, `topicMgr.topics`, etc.) into local lets at the outer `@MainActor` closure scope:

```swift
@MainActor
final class ContentView { /* ... */
    private func constructManagers(for nexus: Nexus) {
        let spaceMgr = SpaceManager(nexus: nexus)
        let topicMgr = TopicManager(nexus: nexus) { @MainActor in
            // Snapshot live state into Sendable locals; inner closures capture the snapshot
            let spaces = spaceMgr.spaces
            let topics = topicMgr.topics
            let subtopics = topicMgr.subtopicsByParent
            return NexusContext(
                lookupSpace: { id in spaces.first { $0.id == id } },
                lookupTopic: { id in topics.first { $0.id == id } },
                lookupSubtopic: { id in subtopics.values.lazy.flatMap { $0 }.first { $0.id == id } },
                lookupVault: { id in /* via vaultMgr — similar snapshot */ nil }
            )
        }
        // ...
    }
}
```

**One-shot only:** the returned NexusContext is invoked per-validate-call and thrown away. **Do not store the returned NexusContext** in a long-lived closure (e.g. background indexer, search index) — the snapshot would go stale. Validation is a one-shot per-call use; that's the only safe shape today.

A higher-level `NexusCoordinator` aggregating all managers is post-v1 if needed; v1 uses the per-manager `contextProvider` closure pattern above.

---

#### Sandbox + security-scoped access — already solved

`NexusManager` already handles `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` lifecycle. New file writes inside the nexus inherit access from the active resource scope — **no per-write bookmark needed**.

**Discipline:** new entity managers should NOT call `startAccessing` independently. They assume the active Nexus's resource scope is held by `NexusManager`. They read `nexusURL` from the active `Nexus` value and write within that tree.

For EventKit (Agenda layer, Phase 6.5): separate sandbox entitlement (`com.apple.security.personal-information.calendars`) + Info.plist usage description keys + `requestFullAccessTo*` APIs. EventKit is its own access flow, NOT the file-r/w resource scope. Detail → `Features/Agenda.md`.

---

#### SF Symbol picker — `xnth97/SymbolPicker` SPM dep behind `IconPickerSheet` wrapper

Paradigm decision 2026-05-16 (see `// Guidelines//Paradigm-Decisions.md`): use the `xnth97/SymbolPicker` Swift Package wrapped behind Pommora's own `IconPickerSheet` view. Wrapping isolates call sites from the third-party API surface — swapping libraries (or moving to a hand-rolled grid) is a single-file rewrite in the wrapper, no call-site churn.

Wrapper shape:

```swift
import SymbolPicker

struct IconPickerSheet: View {
    let target: SidebarSheet.IconTarget   // .space(Space) | .topic(Topic) | .subtopic(Subtopic) | .vault(Vault)
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager

    @State private var icon: String = ""

    var body: some View {
        SymbolPicker(symbol: $icon)  // library renders own UI; nullable variant exposes a delete-icon button
            .onAppear { icon = currentIcon ?? "" }
            .onChange(of: icon) { _, newValue in
                Task { await save(newIcon: newValue.isEmpty ? nil : newValue); dismiss() }
            }
    }

    // currentIcon + save() switch on `target` to dispatch to the right manager method
}
```

SymbolPicker auto-renders Cancel / clear / done chrome; no need to add it in the wrapper. The wrapper's only responsibility: bind the picked symbol back to the right manager's `updateIcon` method via the `IconTarget` enum.

SPM dep added at branch commit `22e3fc6`. Resolver settled on 1.6.2. No curated default list — the library's full search picker is the only icon-picker UI in v0.2.

---

#### Inline editing principle — managers own writes, embeds dispatch to managers

Every embedded view (in a Context page, in the Homepage) is **a live, fully-editable view of its source** — not a snapshot. Implementation discipline:

- Block stores the **reference** (source entity ID + view config + filters), not a snapshot
- Edits route through the source entity's manager (e.g. checking off a Task in an embedded view calls `AgendaManager.toggleCompleted(...)`)
- Manager atomically writes the source file
- File watcher catches the change → SQLite re-indexes → all embedded views of that entity refresh live

**No separate "embed-edit path" vs "primary-surface edit path."** Same manager, same methods. One source of truth per entity.

Detail → `Planning/Contexts-Vaults-spec.md` "Inline editing in composed-page blocks (Notion-style)."

---

#### Section-extraction discipline (from swiftui-expert-skill)

Per `swiftui-expert-skill/references/view-structure.md`, extract complex view sections into separate `struct: View` types — not `@ViewBuilder` computed properties — so SwiftUI can skip body re-evaluation when inputs don't change. Applies especially to large `SidebarView` sections (Spaces / Topics / Vaults), each of which has independent state sources (one manager each).

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

Target is macOS 26.4. Use modern APIs throughout — Pommora doesn't carry back-deployment burden.
