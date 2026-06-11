## Contexts Decoupling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Projects free-standing tier-3 contexts (no Topic containment), reset all context→context relation machinery to bare entities, redo the sidebar's context area as three disclosure rows, and rename the Space entity to **Area** — per the ratified spec `06-10-Contexts-Decoupling-Spec.md`.

**Architecture:** Five code phases + one docs phase, each shipping green commits. P1 decouples Projects (new `ProjectManager`, flat `.nexus//projects//<Title>//_project.json`). P2 strips Topic parents. P3 builds the sidebar ContextsSection. P4 moves Spaces to folder layout and bumps the index to v12. P5 is the grep-gated Space→Area rename (schema v13). P6 rewrites docs spec-style.

**Tech stack:** SwiftUI (macOS), Swift 6 strict concurrency + ExistentialAny, GRDB (SQLite), Swift Testing (`@Suite`/`@Test`), AtomicJSON file IO.

**Test baseline:** 987 tests green at `main` HEAD (v0.4.0; re-verified 2026-06-10 immediately pre-execution — was 985 at `81396cc`, +2 from the v0.4.0 PagePreview work).

### Standing Rules (every task)

- **Verify via background builder agent** (quirk #13): `xcodebuild test -only-testing:PommoraTests` via a background Agent so window focus is never stolen. ALWAYS confirm a non-zero executed-test count (quirk #1 — filters match `@Suite` names, not filenames).
- **Revert pbxproj SPM-reorder noise before every commit** (quirk #6).
- **Sidebar Section structure is load-bearing** (quirk #8): rows inside one `Section` stay homogeneous; chrome stays at row level via `.listRowBackground(SelectionChrome(...))` (quirk #9). Verify sidebar phases with tests that actually bootstrap.
- **Re-assess this plan between green commits** (CLAUDE.md hard rule): if a task surfaces wrong assumptions, rewrite the affected later tasks before dispatching the next one.
- **Parallel-session gate — CLEARED 2026-06-10.** The PagePreview-window rework landed (`a073fb4` + follow-ups); `SidebarView.swift`, `ContentView.swift`, and `FrontmatterInspector.swift` are all committed, and their plan anchors were re-grounded against the landed files (round 5). Only `Pommora/Pommora/Preview/PagePreviewWindow.swift` remains in the parallel session — it is NOT a plan dependency. Standing hygiene: the build (quirk #3) is the final anchor check; never revert unattributed working-tree changes (quirk #10).
- All line anchors below were verified 2026-06-10 against the working tree. If an anchor doesn't match, STOP and re-locate by symbol name — do not guess.

### Out of Scope (locked by spec)

Pages' `tier1`/`tier2`/`tier3` frontmatter, `BuiltInContextLinkProperties`, `ContextPicker`, the `context_links` table, `cascadeUnlinkTier`, `TierRelationCarrying`, `ReservedPropertyID` — untouched. Context→context relations, roll-up, and composed-blocks surfaces are deferred to a future brainstorming. No data migration (greenfield).

### Verified Ground Truth (what exists today)

| Fact | Anchor |
|---|---|
| `Space`: id/tier(1)/title/color/icon/blocks/modifiedAt; flat file `.nexus//spaces//<Title>.space.json`; title from filename | `Contexts/Space.swift` (72 lines) |
| `Topic`: + `parents: [String]`, `projectOrder: [String]?` (key `project_order`); folder `_topic.json`; title from folder | `Contexts/Topic.swift` (80 lines) |
| `Project`: + `parents`, `projectLinks` (key `project_links`, legacy `linked_relations`); file inside Topic folder | `Contexts/Project.swift` (94 lines) |
| `TopicManager` owns ALL project CRUD via `projectsByParent: [String: [Project]]` | `Contexts/TopicManager.swift:10` |
| Project APIs to delete: `projects(in:)` :34, `createProject` :306, `renameProject` :356, `moveProject` :423, `deleteProject` :480, `updateProjectIcon` :503, `reorderProjects` :548, `promoteProjectToTopic` :274, `updateTopicParents` :190 | `TopicManager.swift` |
| `NexusPaths`: `spacesDir` :24, `topicsDir` :28, `spaceFileURL` :206, `topicFolderURL` :210, `topicMetadataURL` :214, `projectFileURL(inTopicTitled:)` :219 | `AtomicIO/NexusPaths.swift` |
| `NexusState` has `spaceOrder`/`topicOrder`/`vaultOrder` — NO `projectOrder` | `NavDropdown/NexusState.swift:22-24` |
| `OrderPersister.setProjectOrder(_:in:nexus:)` writes the TOPIC sidecar | `Ordering/OrderPersister.swift:41-46` |
| `contexts` table: `id, tier, title, icon, parent_topic_id`; `idx_contexts_parent_topic` | `Index/IndexSchema.swift:76-84, 138` |
| `currentSchemaVersion = 11` | `Index/PommoraIndex.swift:93` |
| `IndexUpdater.upsertContext` ×3 write `parent_topic_id` | `Index/IndexUpdater.swift:251-291` |
| `IndexBuilder.collectContexts` walks spaces flat files + topic folders + nested projects; `ContextSnapshot.parentTopicID` :72; `insertContexts` SQL :489-502 | `Index/IndexBuilder.swift` |
| `ProjectValidator` enforces exactly-one-parent + folder-name match | `Validation/ProjectValidator.swift:35-46` |
| `TopicValidator` resolves each parent to a Space via `context.lookupSpace` | `Validation/TopicValidator.swift:30-34` |
| `SidebarSelection.resolveProject` iterates `projectsByParent`; `SidebarLookupBundle` has no project manager | `Sidebar/SidebarSelection.swift:75-81, 46-51` |
| `TopicRow` = DisclosureGroup over `projects(in:)`; "Edit Parents" :92; `ParentSpaceTags` :187-206 | `Sidebar/TopicRow.swift` |
| `ProjectRow` requires `parentTopic: Topic` :6; renames via `topicManager` :69 | `Sidebar/ProjectRow.swift` |
| `SidebarView`: SpacesSection :382-441, TopicsSection :443-502, delete-topic promote flow :169-202, `cascadeUnlinkTier` :238-243 | `Sidebar/SidebarView.swift` |
| `SidebarConfirmation.deleteTopic(Topic, projectCount: Int)` | `Sidebar/SidebarConfirmation.swift:6` |
| `SidebarSheet.editTopicParents(Topic)` | `Sidebar/Sheets/SidebarSheet.swift:12` |
| Detail: Topic placeholder "Parents: …" + `parentSpaceNames` | `Detail/SidebarDetailView.swift:43, 169-173` |
| Labels: `SettingsLabels` sidebarSections `spaces/topics/pages` (no `projects`); `TierConfig` defaults Space/Topic/Project | `Settings/SettingsLabels.swift:39-48`, `Contexts/TierConfig.swift:32-34` |
| Kind strings `"space"/"topic"/"project"`: `EntityKind` (IndexQuery.swift:600), `kindTableMap` (IndexQuery.swift:13-26), `RelationTargetKind` (:20-22) | `Index/*` |

Full touchpoint census, rename map, and test census live in the agent reports summarized in this plan; the spec is `06-10-Contexts-Decoupling-Spec.md`.

### File Structure (created // deleted)

```
CREATE  Pommora//Pommora//Contexts//ProjectManager.swift          (P1 — sibling of SpaceManager)
CREATE  Pommora//Pommora//Sidebar//ContextsSection.swift           (P3 — section + TierDisclosureRow)
CREATE  Pommora//PommoraTests//Contexts//ProjectManagerTests.swift (P1)
DELETE  Pommora//Pommora//Sidebar//Sheets//EditTopicParentsSheet.swift (P2)
RENAME  Space.swift→Area.swift, SpaceColor.swift→AreaColor.swift, SpaceManager.swift→AreaManager.swift,
        SpaceRow.swift→AreaRow.swift, SpaceColorPicker.swift→AreaColorPicker.swift,
        SpaceValidator.swift→AreaValidator.swift (+3 test files)     (P5)
```

---

### P1 — Project Decoupling

#### Task 1.1: Additive plumbing (paths, state, order)

**Files:** Modify `Pommora/Pommora/AtomicIO/NexusPaths.swift`, `Pommora/Pommora/NavDropdown/NexusState.swift`, `Pommora/Pommora/Ordering/OrderPersister.swift`. Tests: `Pommora/PommoraTests/NavDropdown/` (NexusState round-trip suite — locate by `grep -rn "NexusState" Pommora/PommoraTests --include="*.swift" -l`).

- [ ] **Step 1:** In `NexusPaths.swift` after `topicsDir` (:28-30), add:

```swift
static func projectsDir(in nexus: Nexus) -> URL {
    nexusConfigDir(in: nexus).appendingPathComponent("projects", isDirectory: true)
}
```

- [ ] **Step 2:** In `NexusPaths.swift` "Contexts file paths" section (after :226), add (delete `projectFileURL(inTopicTitled:)` in Task 1.3, not yet):

```swift
static func projectFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
    projectsDir(in: nexus).appendingPathComponent(title, isDirectory: true)
}

static func projectMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
    projectFolderURL(forTitle: title, in: nexus)
        .appendingPathComponent("_project.json", isDirectory: false)
}
```

- [ ] **Step 3:** In `NexusState.swift`: add `var projectOrder: [String]?` after `topicOrder` (:23); add `case projectOrder = "project_order"` to CodingKeys after :35; add decode line `self.projectOrder = try c.decodeIfPresent([String].self, forKey: .projectOrder)` after :49; add encode line `try c.encodeIfPresent(projectOrder, forKey: .projectOrder)` after :60.

- [ ] **Step 4:** In `OrderPersister.swift` "Top-level (state.json)" section (after :31), add the flat overload (the old topic-sidecar `setProjectOrder` :41-46 dies in Task 1.3):

```swift
static func setProjectOrder(_ order: [String], in nexus: Nexus) throws {
    try mutateNexusState(in: nexus) { state in
        state.projectOrder = order.isEmpty ? nil : order
    }
}
```

- [ ] **Step 5:** Add a round-trip test to the existing NexusState suite (match its existing test shape) asserting `project_order` encodes/decodes and tolerates absence.
- [ ] **Step 6:** Verify via background builder (`-only-testing:PommoraTests`), confirm non-zero count, all green.
- [ ] **Step 7:** Commit: `feat(contexts): add flat project paths + project_order state plumbing`

#### Task 1.2: ProjectManager + bare ProjectValidator (additive, unused)

**Files:** Create `Pommora/Pommora/Contexts/ProjectManager.swift`; modify `Pommora/Pommora/Validation/ProjectValidator.swift` (ADD a bare overload below the existing `validate` — existing code untouched); create `Pommora/PommoraTests/Contexts/ProjectManagerTests.swift`. NOTE (Files-line corrected during execution): `ProjectValidatorTests.swift` is NOT touched this task — it still exercises the legacy 6-param overload, which still exists; its rewrite for the bare overload happens in Task 1.3 Step 17.

**Compile note (zero throwaway code):** `TopicManager.createProject`/`renameProject` call the legacy 6-param `ProjectValidator.validate(title:parents:fileLocation:existing:context:excluding:)`. This task does NOT touch that signature — it adds the bare overload BESIDE it (pure addition; the legacy `ValidationError` enum already carries `emptyTitle`/`invalidTitleCharacters`/`duplicateTitle`, so the new overload reuses it). Task 1.3 deletes the legacy signature, `FileLocation`, and the parent error cases in the same commit that deletes their only callers. No stub, no double-edit.

- [ ] **Step 1:** In `ProjectValidator.swift`, ADD the bare overload below the existing `validate` (existing code untouched):

```swift
/// Bare title validation for free-standing tier-3 Projects (Contexts
/// Decoupling). The legacy parent/containment overload above is deleted
/// in Task 1.3 along with its last callers in TopicManager.
static func validate(
    title: String,
    existing: [Project],
    excluding: Project? = nil
) throws {
    let trimmed = title.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }

    let invalidChars: Set<Character> = ["/", "\\", ":"]
    guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
        throw ValidationError.invalidTitleCharacters
    }

    let conflict = existing.contains { p in
        p.id != excluding?.id && p.title.lowercased() == trimmed.lowercased()
    }
    if conflict { throw ValidationError.duplicateTitle }
}
```

- [ ] **Step 2:** Create `ProjectManager.swift` in full — `SpaceManager`'s shape (loadAll + defensive index sync per quirk #14, create, rename with `RenameAtomicityError` rollback mirroring `renameTopic` :139-188, updateIcon, reorder, delete) on the folder + `_project.json` layout. Until Task 1.3 rewrites the entity, construct with `parents: [], projectLinks: []`:

```swift
import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderProjects

@MainActor
@Observable
final class ProjectManager {
    private(set) var projects: [Project] = []
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    /// Injected by ContentView.constructManagers. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is
    /// canonical). Projects index into `contexts` as tier 3 via
    /// `upsertContext(_:)` — without this, the tier-3 picker never sees
    /// Projects created/edited since the last full IndexBuilder rebuild.
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.projectsDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            var loaded: [Project] = []
            let folders = try Filesystem.childFolders(of: dir)
            for folder in folders {
                let metaURL = folder.appendingPathComponent("_project.json")
                guard Filesystem.fileExists(at: metaURL) else { continue }  // skip cosmetic folder
                guard let project = try? Project.load(from: metaURL) else { continue }
                loaded.append(project)
            }
            self.projects = OrderResolver.resolve(
                loaded,
                persistedOrder: readPersistedProjectOrder(),
                titleKeyPath: \Project.title
            )
            self.pendingError = nil

            // Defensive index sync (quirk #14). Projects arriving outside CRUD
            // must land in `contexts` so the tier-3 picker can surface them.
            // INSERT OR REPLACE is idempotent; failures swallowed (index is
            // regeneratable, no user data lost).
            if let updater = indexUpdater {
                for project in self.projects {
                    try? updater.upsertContext(project)
                }
            }
        } catch {
            self.projects = []
            self.pendingError = error
        }
    }

    @discardableResult
    func create(name: String, icon: String?) async throws -> Project {
        do {
            try ProjectValidator.validate(title: name, existing: projects)

            let project = Project(
                id: ULID.generate(),
                title: name,
                parents: [],          // field removed in Task 1.3
                projectLinks: [],     // field removed in Task 1.3
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.projectFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.projectMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: project)

            if let updater = indexUpdater {
                do { try updater.upsertContext(project) } catch { self.pendingError = error }
            }

            projects.append(project)
            projects = OrderResolver.resolve(
                projects,
                persistedOrder: readPersistedProjectOrder(),
                titleKeyPath: \Project.title
            )
            return project
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func rename(_ project: Project, to newName: String) async throws {
        do {
            try ProjectValidator.validate(title: newName, existing: projects, excluding: project)

            let oldFolder = NexusPaths.projectFolderURL(forTitle: project.title, in: nexus)
            let newFolder = NexusPaths.projectFolderURL(forTitle: newName, in: nexus)
            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = project
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.projectMetadataURL(forTitle: newName, in: nexus)
            do {
                try updated.save(to: newMeta)
            } catch let saveError {
                // Roll back the folder rename. If revert fails, on-disk state
                // is inconsistent — surface with RenameAtomicityError.
                do {
                    try Filesystem.renameFolder(from: newFolder, to: oldFolder)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertContext(updated) } catch { self.pendingError = error }
            }

            if let i = projects.firstIndex(where: { $0.id == project.id }) {
                projects[i] = updated
                projects = OrderResolver.resolve(
                    projects,
                    persistedOrder: readPersistedProjectOrder(),
                    titleKeyPath: \Project.title
                )
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateIcon(_ project: Project, to icon: String?) async throws {
        do {
            var updated = project
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.projectMetadataURL(forTitle: project.title, in: nexus)
            try updated.save(to: meta)
            // `icon` is an indexed `contexts` column — re-upsert.
            if let updater = indexUpdater {
                do { try updater.upsertContext(updated) } catch { self.pendingError = error }
            }
            if let i = projects.firstIndex(where: { $0.id == project.id }) {
                projects[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Projects in response to a sidebar drag. Matches the SwiftUI
    /// `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = projects
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != projects else { return }
        projects = arr
        do {
            try OrderPersister.setProjectOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    func delete(_ project: Project) async throws {
        do {
            let folder = NexusPaths.projectFolderURL(forTitle: project.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            // Drop the stale `contexts` row.
            if let updater = indexUpdater {
                do { try updater.deleteContext(id: project.id) } catch { self.pendingError = error }
            }
            projects.removeAll { $0.id == project.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reads the persisted Project sibling order from `.nexus/state.json`.
    private func readPersistedProjectOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.projectOrder
    }
}
```

- [ ] **Step 3:** Create `ProjectManagerTests.swift`, `@Suite("ProjectManager")`, mirroring `SpaceManagerTests` cases against a temp-dir nexus: `create()` writes `.nexus/projects/<Title>/_project.json` + appends to `projects`; `createDuplicate()` throws, disk unchanged; `rename()` renames the folder + updates in-memory entry; `updateIcon()` mutates icon + bumps `modified_at` on disk; `delete()` trashes folder + drops from array. DEFER the `loadAll`-fixture test to Task 1.3 Step 17 (until the entity rewrite lands, `Project.load` still derives title from FILENAME, so a `_project.json` fixture would title itself "_project"). Hoist `let id = ULID.generate()` before entity construction (quirk #5). Legacy `ProjectValidatorTests` stay untouched this task (they exercise the legacy overload, which still exists).
- [ ] **Step 4:** Background-builder verify; non-zero count; green.
- [ ] **Step 5:** Commit: `feat(contexts): ProjectManager + bare ProjectValidator overload (flat tier-3, unused until pivot)`

#### Task 1.3: The pivot — entity rewrite, TopicManager strip, env + index + UI compile-closure

One commit. Every step is required for the build to go green again; execute in order, then build once.

**Files:** Rewrite `Contexts/Project.swift`; modify `Contexts/Topic.swift`, `Contexts/TopicManager.swift`, `Contexts/ProjectManager.swift`, `Ordering/OrderPersister.swift`, `AtomicIO/NexusPaths.swift`, `Index/IndexBuilder.swift`, `Index/IndexUpdater.swift`, `Nexus/NexusEnvironment.swift`, `Validation/NexusContext.swift` (comment only), `Sidebar/SidebarSelection.swift`, `Sidebar/TopicRow.swift`, `Sidebar/ProjectRow.swift`, `Sidebar/SidebarView.swift`, `Sidebar/SidebarConfirmation.swift`, plus every `SidebarLookupBundle(...)` construction site (`grep -rn "SidebarLookupBundle(" Pommora/Pommora` — verified set: `SidebarView.swift:71`, `ContentView.swift:93`, `ContentView.swift:170`; BackForwardButtons/NavDropdownButton only RECEIVE a bundle, they don't construct one. ContentView has landed — re-confirm cheaply at execution via the grep). Tests: `TopicManagerTests`, `ProjectFileTests`, `TopicFileTests` (projectOrder cases only), `ManagerCreateReturnContractTests`, `LoadAllIndexSyncTests`, `ProjectManagerTests`.

- [ ] **Step 1:** Rewrite `Contexts/Project.swift` in full — bare entity, folder sidecar, title from parent folder (Topic.load's idiom):

```swift
import Foundation

/// Tier-3 Context entity — free-standing (Contexts Decoupling).
/// On disk: `.nexus/projects/<Title>/_project.json` (folder = title; no title on disk).
struct Project: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String  // ULID
    var tier: Int  // always 3
    var title: String  // derived from parent folder name on load
    var icon: String?  // SF Symbol name
    var blocks: [ContextBlock]
    var modifiedAt: Date

    init(
        id: String,
        title: String,
        icon: String?,
        blocks: [ContextBlock],
        modifiedAt: Date
    ) {
        self.id = id
        self.tier = 3
        self.title = title
        self.icon = icon
        self.blocks = blocks
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tier, icon, blocks
        case modifiedAt = "modified_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.tier = try c.decodeIfPresent(Int.self, forKey: .tier) ?? 3
        self.title = ""  // caller (load(from:)) overwrites from folder name
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.blocks = try c.decodeIfPresent([ContextBlock].self, forKey: .blocks) ?? []
        self.modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(3, forKey: .tier)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension Project {
    /// Loads `_project.json` and derives `title` from the parent folder name.
    static func load(from metadataURL: URL) throws -> Project {
        var p = try AtomicJSON.decode(Project.self, from: metadataURL)
        p.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return p
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
```

- [ ] **Step 2:** `Contexts/Topic.swift` — delete `projectOrder` entirely: property + doc comment (:14-17), init param + assignment (:26, :35), CodingKey (:41), decode (:53), encode (:64). (`parents` stays until P2.)
- [ ] **Step 3:** `Contexts/TopicManager.swift` — delete: `projectsByParent` (:9-10), `projects(in:)` (:32-36), the project-scanning half of `loadAll` (:46, :55-68 — keep the topic scan; `loadedProjects` and the per-topic project upsert loop :87-89 go), `projectsByParent[topic.id] = []` in `createTopic` (:126), the whole `deleteTopic` promote path + project rows (:244-250, :261-263, :267 — new body below), `promoteProjectToTopic` (:274-301), ALL of "Project CRUD" (:303-529), and `reorderProjects` (:546-564). **Keep `updateTopicParents` (:190-217) — do NOT delete it in this commit (round-4 fix):** its only caller is `EditTopicParentsSheet.swift:57`, which survives until P2.1; deleting the method here reds the build. It dies in P2.2 Step 3, in the same commit that strips `Topic.parents`. Then in `Validation/ProjectValidator.swift` delete the legacy 6-param `validate`, the `FileLocation` struct, and the now-unreferenced error cases `missingParent`/`tooManyParents`/`parentNotFound`/`fileLocationMismatch` (their only callers died with the CRUD above). New `deleteTopic`:

```swift
func deleteTopic(_ topic: Topic) async throws {
    do {
        let folder = NexusPaths.topicFolderURL(forTitle: topic.title, in: nexus)
        try Filesystem.moveToTrash(folder, in: nexus)
        if let updater = indexUpdater {
            do { try updater.deleteContext(id: topic.id) } catch { self.pendingError = error }
        }
        topics.removeAll { $0.id == topic.id }
    } catch {
        self.pendingError = error
        throw error
    }
}
```

- [ ] **Step 4:** `Contexts/ProjectManager.swift` — update `create` to the new init: `Project(id: ULID.generate(), title: name, icon: icon, blocks: [], modifiedAt: Date())`. Remove the two `// field removed in Task 1.3` lines. **ALSO (post-Task-1.2 cleanup):** remove the now-redundant `project.title = folder.lastPathComponent` line + its comment from `loadAll` — Task 1.2 added it as a workaround for the old filename-based `Project.load`; once Step 1 rewrites `Project.load` to derive title from the folder, `load` does this internally and the patch is dead.
- [ ] **Step 5:** `Ordering/OrderPersister.swift` — delete the **topic-sidecar** overload `setProjectOrder(_ order:, in topic: Topic, nexus: Nexus)` — the one calling `Topic.load` / `NexusPaths.topicMetadataURL`, now at **:47-52** (Task 1.1 shifted it down) — and its `// MARK: - Project order (_topic.json)` (:45). **KEEP the flat `setProjectOrder(_ order:, in nexus: Nexus)` at :39-43 (state.json) — that's Task 1.1's overload, NOT a deletion target.** Update the header doc comment list (:5-11) to drop the Topic bullet. (Anchor corrected post-Task-1.1: the original `:39-46` now points at the flat overload to KEEP — delete by SIGNATURE `in topic: Topic`, not by line.)
- [ ] **Step 6:** `AtomicIO/NexusPaths.swift` — delete `projectFileURL(forTitle:inTopicTitled:in:)` (:219-226).
- [ ] **Step 7:** `Index/IndexBuilder.swift` — in `collectContexts` (:298-341): delete the nested-projects loop (:327-336); topics append with `parentTopicID: nil` (unchanged); add after the topics block:

```swift
// Projects (tier 3) — free-standing folders
let projectsDir = NexusPaths.projectsDir(in: nexus)
if Filesystem.folderExists(at: projectsDir) {
    let projectFolders = (try? Filesystem.childFolders(of: projectsDir)) ?? []
    for folder in projectFolders {
        let metaURL = folder.appendingPathComponent("_project.json")
        guard Filesystem.fileExists(at: metaURL),
            let project = try? Project.load(from: metaURL)
        else { continue }
        result.append(
            ContextSnapshot(id: project.id, tier: 3, title: project.title, icon: project.icon, parentTopicID: nil))
    }
}
```

- [ ] **Step 8:** `Index/IndexUpdater.swift` — `upsertContext(_ project:)` (:279-291): replace `let parentTopicID = project.parents.first` with nothing and pass `nil` as the last argument (column survives until P4).
- [ ] **Step 9:** `Nexus/NexusEnvironment.swift` — add stored property `let projectManager: ProjectManager`; construct `let projectMgr = ProjectManager(nexus: nexus)` alongside `spaceMgr`/`topicMgr` (init body :82-155); add `.environment(env.projectManager)` in `injectNexusEnvironment` next to :231-232; rewrite the `lookupProject` closure (:106-122) using the snapshot-closure idiom (quirk #5):

```swift
let projectsSnapshot = projectMgr.projects
// ...
lookupProject: { id in projectsSnapshot.first(where: { $0.id == id }) }
```

  Then `grep -rn "indexUpdater = " Pommora/Pommora --include="*.swift"` and wire `projectMgr.indexUpdater` wherever `spaceMgr.indexUpdater` is assigned; `grep -rn "spaceManager.loadAll\|spaceMgr.loadAll" Pommora/Pommora` and add the matching `projectManager.loadAll()` call beside it. BEFORE moving on, confirm (quirk #15 — missed injection SIGTRAPs at runtime, not compile time): `.environment(env.projectManager)` exists in `injectNexusEnvironment`, and `grep -rn "SidebarLookupBundle(" Pommora/Pommora` shows every construction passing `project:`. Do NOT add a `projectManager` slot to `AppGlobals.publish` (round-4 watch-item) — cross-scene readers (PagePreviewWindow, ComponentLibraryView, ViewSettingsButton) read `AppGlobals.current` (the whole environment) and re-inject via `injectNexusEnvironment`; the per-manager slots there are effectively dead, so a new one would be dead code.
- [ ] **Step 10:** `Sidebar/SidebarSelection.swift` — add `let project: ProjectManager?` to `SidebarLookupBundle` (:46-51); rewrite `resolveProject` (:74-81):

```swift
@MainActor
private static func resolveProject(id: String, lookup: SidebarLookupBundle) -> SidebarSelection? {
    guard let pm = lookup.project, let p = pm.projects.first(where: { $0.id == id }) else { return nil }
    return .project(p)
}
```

  Update every `SidebarLookupBundle(...)` construction site to pass `project:` — verified set: `SidebarView.swift:71`, `ContentView.swift:93`, `ContentView.swift:170` (BackForwardButtons/NavDropdownButton only RECEIVE a bundle; ContentView has landed — drive by grep, re-confirm cheaply at execution).
- [ ] **Step 11:** `Sidebar/TopicRow.swift` — remove the DisclosureGroup: body becomes the `label` content directly with `.listRowBackground(...)` (keep chrome at row level, quirk #9); delete the ForEach/`.onMove` (:23-45), `createProject()` (:133-158), `isCreatingProject` (:20), the "New \(projectLabel)" button (:85, :88-89), and the `projectCount:` argument (:96 → `confirmingDelete = .deleteTopic(topic)`). Keep `ParentSpaceTags` (dies in P2).
- [ ] **Step 12:** `Sidebar/ProjectRow.swift` — delete `let parentTopic: Topic` (:6); swap `@Environment(TopicManager.self)` → `@Environment(ProjectManager.self) private var projectManager` (:13); `commit()` calls `try await projectManager.rename(project, to: draft)` (:69).
- [ ] **Step 13:** `Sidebar/SidebarConfirmation.swift` — `case deleteTopic(Topic, projectCount: Int)` → `case deleteTopic(Topic)`; fix `id` (:14).
- [ ] **Step 14:** `Sidebar/SidebarView.swift` — confirmation surfaces: `.deleteTopic(let t, _)` → `.deleteTopic(let t)` (:136); message (:147-150) → `return "This action cannot be undone."`; replace the whole `.deleteTopic` button block (:169-202) with the single-delete shape used by `.deleteSpace`, calling `try await topicManager.deleteTopic(t)` after `cascadeUnlinkTier(contextID: t.id, tier: 2)`; in `.deleteProject` (:203-212) replace `try await topicManager.deleteProject(p)` with `try await projectManager.delete(p)` (add `@Environment(ProjectManager.self) private var projectManager`).
- [ ] **Step 15:** `Sidebar/Sheets/IconPickerSheet.swift:68` — replace `try await topicManager.updateProjectIcon(p, to: newIcon)` with `try await projectManager.updateIcon(p, to: newIcon)`; add `@Environment(ProjectManager.self) private var projectManager` and drop the `topicManager` env var if the `.project` branch was its last use.
- [ ] **Step 16:** `Sidebar/SidebarToast.swift` — it aggregates `pendingError` from spaceManager / topicManager / vaultManager / contentManager (+savedConfig/sidebarSections) but not projects. Four wiring points, mirroring the existing pattern exactly: (a) `@Environment(ProjectManager.self) private var projectManager`; (b) `case project` added to `enum ErrorSource: String` (:26-28); (c) an `.onChange` capture for `projectManager.pendingError` beside the existing ones (:56-73); (d) `case .project: projectManager.pendingError = nil` in the dismiss/clear switch (~:84-90). Omitting (b)–(d) compiles fine but silently swallows every ProjectManager error.
- [ ] **Step 17:** Tests. `TopicManagerTests`: delete `createProject`, `deletePromote`, `moveProject` tests; update `deleteTopic` test to the new signature; update `createTopic` if it asserted `projectsByParent` seeding. `ProjectFileTests`: rewrite round-trip for bare schema (`id`/`tier`/`icon`/`blocks`/`modified_at` only; title from folder name; assert `parents`/`project_links`/`linked_relations` keys absent on encode and IGNORED on decode). `TopicFileTests`: drop `project_order` round-trip assertions. `ManagerCreateReturnContractTests`: `createProjectReturns` now exercises `ProjectManager.create`. `ProjectValidatorTests`: rewrite for the bare overload (mirror `SpaceValidatorTests`: `nonEmptyPasses`, `emptyFails`, `whitespaceFails`, `slashFails`, `backslashFails`, `colonFails`, `duplicateFails` case-insensitive, `renameToSelfPasses`); delete `zeroParents`/`tooManyParents`/`parentNotFound`/`locationMismatch`. `ProjectManagerTests`: add the deferred `loadAll` fixture test (write `.nexus/projects/Fixture/_project.json`, `loadAll`, assert title == "Fixture"). `LoadAllIndexSyncTests`: add a project case — same fixture, assert a tier-3 `contexts` row exists. Census additions (third-pass findings): `NexusPathsTests.swift:176` — delete the `projectFileURL` path test (API deleted this task); `ViewSettingsScopeMappingTests.swift` — update its `Project(...)` fixture to the bare initializer (drop `parents:`/`projectLinks:`). NOTE: `TopicManagerTests` keeps its surviving topic-CRUD tests — delete only the project/promote methods; `createTopic(parents:)` calls in it survive until P2.
- [ ] **Step 18:** Background-builder verify full `PommoraTests`; non-zero count; green. Expect count to DROP (deleted containment tests) — record the new baseline in the commit message.
- [ ] **Step 19:** Commit: `refactor(contexts)!: decouple Projects — flat .nexus/projects, ProjectManager, containment CRUD deleted`

---

### P2 — Topic Parents Strip

#### Task 2.1: Delete the parents UI

**Files:** Delete `Sidebar/Sheets/EditTopicParentsSheet.swift`; modify `Sidebar/Sheets/SidebarSheet.swift`, `Sidebar/SidebarView.swift`, `Sidebar/TopicRow.swift`, `Detail/SidebarDetailView.swift`, `Contexts/TopicManager.swift`.

- [ ] **Step 1:** Delete file `EditTopicParentsSheet.swift`.
- [ ] **Step 2:** `SidebarSheet.swift` — delete `case editTopicParents(Topic)` (:12) and its `id` line (:29); update the doc comment (:10).
- [ ] **Step 3:** Delete the `.editTopicParents` case from BOTH `.sheet` switches: `SidebarView.swift:113` AND `SidebarDetailView.swift:121` (the detail pane presents the same sheet — second-pass finding).
- [ ] **Step 4:** `TopicRow.swift` — delete `Button("Edit Parents")` (:92); delete the whole `ParentSpaceTags` struct (:186-206), both `trailing:` closures passing it (:69-71, :80-82), and `@Environment(SpaceManager.self)` (:13) if now unused. **ALSO (Task-1.3 carry-forward):** delete the now-orphaned `@Environment(SettingsManager.self) private var settingsManager` (dead since 1.3 flattened TopicRow — its only use was the deleted "New Project" label).
- [ ] **Step 5:** `SidebarDetailView.swift` — Topic placeholder `supportingLine` (:43) → `"Tier 2 — Topic"`; delete `parentSpaceNames` (:169-173).
- [ ] **Step 6:** Background-builder verify; green. Commit: `refactor(contexts): delete topic parents UI (sheet, dots, breadcrumb)`

#### Task 2.2: Bare Topic entity + validator

**Files:** Modify `Contexts/Topic.swift`, `Validation/TopicValidator.swift`, `Contexts/TopicManager.swift`, `Index/IndexUpdater.swift`, `Nexus/NexusEnvironment.swift`, `Sidebar/SidebarView.swift`, `Sidebar/TopicRow.swift`. Tests: `TopicFileTests`, `TopicValidatorTests`.

- [ ] **Step 1:** `Topic.swift` — delete `parents`: property (:9), init param + assignment (:22, :31), CodingKey (:39), decode (:49), encode (:60). Update the type doc comment (:3) to "Tier-2 Context entity — free-standing."
- [ ] **Step 2:** `TopicValidator.swift` — drop `parents`/`context` params and the `parentNotFound` case; final shape mirrors the bare `ProjectValidator` from Task 1.2 Step 1 (same three errors; `NameCollisionValidator.validate(desiredTitle:siblings:excludingID:else:)` stays for the duplicate check as today :26-28).
- [ ] **Step 3:** `TopicManager.swift` — delete `updateTopicParents` (:190-217) (deferred here from P1.3; now caller-free after P2.1 deleted `EditTopicParentsSheet`, and it references `Topic.parents` which Step 1 removes, so it MUST die in THIS commit); `createTopic(name:parents:icon:)` → `createTopic(name:icon:)` (Topic init loses `parents:`); `renameTopic`'s validate call (:141-145) drops `parents`/`context`. The `contextProvider()` references disappear WITH those two validate-call rewrites (its only remaining uses after P1) — then delete the stored property (:14) + init param (:27-30), update the `TopicManager(...)` construction in `NexusEnvironment.swift`, AND `grep -rn "TopicManager(" Pommora/PommoraTests` to drop the `contextProvider:` argument from each of the ~8 INLINE `TopicManager(...)` constructions it finds — `TopicManagerTests.swift:135`, `FolderExclusionDiscoveryTests.swift:218/223`, `ManagerCreateReturnContractTests.swift:62/74`, `IndexBuilderTests.swift:277`, `IndexPopulationReproTests.swift:112/296` (round-4 fix: these are INLINE per-file, NOT a shared helper); leave every `PageContentManager(...contextProvider:...)` construction untouched — that manager keeps its provider. The locked `@MainActor @escaping () -> NexusContext` pattern simply has one fewer consumer — `NexusContext` itself stays for page validation.
- [ ] **Step 4:** Call sites: `TopicRow.createTopic` (:118-120) and `SidebarView.TopicsSection.createTopic` (:490) drop the `parents:` argument.
- [ ] **Step 5:** `IndexUpdater.upsertContext(_ topic:)` (:264-277) — delete the `firstParent` line, pass `nil` (column survives until P4).
- [ ] **Step 6:** Tests: `TopicFileTests` — delete `zeroParents` + parents round-trip assertions; assert `parents` key ignored on decode, absent on encode. `TopicValidatorTests` — delete `emptyParents`/`parentMissing`/`parentResolves`; keep title + duplicate cases; its `makeTopic(title:parents:)` helper drops the `parents:` param (one definition fixes all call sites). Census additions (third-pass findings) — drop the `parents:` argument from `createTopic`/`Topic(...)` at every site: `ManagerCreateReturnContractTests` (×2 createTopic), `IndexBuilderTests.swift:289`, `FolderExclusionDiscoveryTests.swift:219`, `RebuildResilienceTests.swift:83-84` (Topic fixture), `IndexPopulationReproTests.swift:100-101` (Topic fixture), `ViewSettingsScopeMappingTests` (Topic fixture), `TopicManagerTests` (×6 createTopic calls), `EntitiesByTargetGroupedTests` (check fixtures).
- [ ] **Step 7:** Background-builder verify; green. Commit: `refactor(contexts)!: Topic drops parents — bare tier-2 entity`

---

### P3 — Sidebar ContextsSection

#### Task 3.1: TierDisclosureRow + ContextsSection

**Files:** Create `Sidebar/ContextsSection.swift`; modify `Sidebar/SidebarView.swift` (delete `SpacesSection` :382-441 and `TopicsSection` :443-502; replace their two call sites :32-45 with one `ContextsSection`).

**Label sources (second-pass ruling — no new settings surface):** Spaces/Topics tier rows read the EXISTING `sidebarSections.spaces`/`sidebarSections.topics`; the Projects tier row reuses the EXISTING `labels.project.plural`. Do NOT add a `sidebarSections.projects` key — a strip refactor adds no settings machinery; unifying label sources is future settings-UI work.

**Shape rules (quirk #8):** ONE headerless `Section` containing exactly three `TierDisclosureRow`s — homogeneous siblings. The tier rows carry NO `.tag` (never selectable; clicking toggles disclosure). Children (`SpaceRow`/`TopicRow`/`ProjectRow`) keep their existing `.tag` + row-level `SelectionChrome`. This mirrors the proven `Section { PageTypeRow… }` disclosure shape.

- [ ] **Step 1:** Create `Sidebar/ContextsSection.swift`:

```swift
import SwiftUI

/// The sidebar's context area (Contexts Decoupling): ONE headerless Section
/// holding exactly three TierDisclosureRows — homogeneous siblings (quirk #8).
/// Tier rows are expand/collapse only; entity rows inside keep selection.
struct ContextsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?

    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        Section {
            TierDisclosureRow(
                label: settingsManager.settings.labels.sidebarSections.spaces,
                createLabel: "Space",
                onCreate: { createSpace() }
            ) {
                ForEach(spaceManager.spaces) { space in
                    SpaceRow(
                        space: space,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.space(space.id))
                }
                .onMove { source, destination in
                    withAnimation(.snappy) {
                        spaceManager.reorderSpaces(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            TierDisclosureRow(
                label: settingsManager.settings.labels.sidebarSections.topics,
                createLabel: "Topic",
                onCreate: { createTopic() }
            ) {
                ForEach(topicManager.topics) { topic in
                    TopicRow(
                        topic: topic,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.topic(topic.id))
                }
                .onMove { source, destination in
                    withAnimation(.snappy) {
                        topicManager.reorderTopics(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            TierDisclosureRow(
                // Reuses the existing entity label pair — no new settings key
                // (second-pass ruling; sidebarSections gains nothing).
                label: settingsManager.settings.labels.project.plural,
                createLabel: settingsManager.settings.labels.project.singular,
                onCreate: { createProject() }
            ) {
                ForEach(projectManager.projects) { project in
                    ProjectRow(
                        project: project,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                    .tag(SelectionTag.project(project.id))
                }
                .onMove { source, destination in
                    withAnimation(.snappy) {
                        projectManager.reorderProjects(fromOffsets: source, toOffset: destination)
                    }
                }
            }
        }
    }

    // Stub-and-edit creation flows — bodies MOVED VERBATIM from the deleted
    // SpacesSection.createSpace / TopicsSection.createTopic (SidebarView
    // :419-440 / :480-501, minus the dropped parents: argument) and TopicRow's
    // deleted createProject, re-pointed at projectManager.create(name:icon:).
    @State private var isCreatingSpace: Bool = false
    @State private var isCreatingTopic: Bool = false
    @State private var isCreatingProject: Bool = false

    private func createSpace() {
        guard !isCreatingSpace else { return }
        isCreatingSpace = true
        let existing = spaceManager.spaces.map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Space", existingTitles: existing)
        Task {
            defer { isCreatingSpace = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await spaceManager.create(name: title, color: nil, icon: nil) },
                    onCreate: { editingID = $0.id; justCreatedID = $0.id }
                )
            } catch { /* pendingError set by manager; toast surfaces */ }
        }
    }

    private func createTopic() {
        guard !isCreatingTopic else { return }
        isCreatingTopic = true
        let existing = topicManager.topics.map(\.title)
        let title = DefaultTitleResolver.resolve(label: "Topic", existingTitles: existing)
        Task {
            defer { isCreatingTopic = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await topicManager.createTopic(name: title, icon: nil) },
                    onCreate: { editingID = $0.id; justCreatedID = $0.id }
                )
            } catch { /* pendingError set by manager; toast surfaces */ }
        }
    }

    private func createProject() {
        guard !isCreatingProject else { return }
        isCreatingProject = true
        let label = settingsManager.settings.labels.project.singular
        let existing = projectManager.projects.map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreatingProject = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: { try await projectManager.create(name: title, icon: nil) },
                    onCreate: { editingID = $0.id; justCreatedID = $0.id }
                )
            } catch { /* pendingError set by manager; toast surfaces */ }
        }
    }
}

/// A tier container row: DisclosureGroup whose label is `square.grid2x2` +
/// the tier's settings label. Expand/collapse only — NO `.tag`, never
/// selectable. Creation: context menu + hover "+" (the affordances the old
/// SectionHeader carried).
struct TierDisclosureRow<Children: View>: View {
    let label: String
    let createLabel: String
    let onCreate: () -> Void
    @ViewBuilder let children: () -> Children

    @State private var expanded: Bool = false
    @State private var hovered: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            children()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16, alignment: .center)
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered ? 1 : 0)
                .allowsHitTesting(hovered)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
            .padding(.leading, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .contextMenu {
                Button("New \(createLabel)") { onCreate() }
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
    }
}
```

  SF Symbol note: the catalog name is `square.grid.2x2` (Nathan wrote `square.grid2x2` — same symbol, dotted form is the valid name).
- [ ] **Step 2:** `SidebarView.swift` — replace the `SpacesSection(...)` + `TopicsSection(...)` calls (:32-45) with one `ContextsSection(selection:editingID:justCreatedID:presentedSheet:confirmingDelete:)`; delete the `SpacesSection` and `TopicsSection` structs (:382-502).
- [ ] **Step 3:** `SpaceRow.swift` / `TopicRow.swift` row-level "New Space"/"New Topic" context-menu items: KEEP (existing affordance, unchanged scope; TopicRow's already lost "New Project" in P1).
- [ ] **Step 4:** Background-builder verify — tests MUST bootstrap, not just compile (quirk #8 regression class). Green. Run the app once via the builder agent for a launch sanity check if any sidebar test is inconclusive.
- [ ] **Step 5:** Commit: `feat(sidebar): ContextsSection — three tier disclosure rows replace Spaces/Topics headings`

#### Task 3.2: Remove the dead sidebar search bar

**Files:** Modify `Pommora/Pommora/ContentView.swift` (PagePreview session has landed — anchors below re-grounded against the committed file 2026-06-10).

The search field is a dead control, verified: `@State private var searchQuery` (:13) is written by the field and read by NOTHING in the codebase (the only other `searchQuery` is PropertiesListPane's own unrelated local).

- [ ] **Step 1:** Delete the `.safeAreaInset(edge: .top, spacing: 8) { SidebarSearchField(text: $searchQuery).padding(.horizontal, 10) }` modifier on `sidebar` (:132-135) — this is also the inset that spaced the field above the first section; nothing replaces it, the sidebar's top edge starts at the pinned rows.
- [ ] **Step 2:** Delete `@State private var searchQuery = ""` (:13).
- [ ] **Step 3:** Delete the entire `private struct SidebarSearchField: NSViewRepresentable` including its `Coordinator` (now :380 after the PagePreview landing; was :382).
- [ ] **Step 4:** `grep -rn "SidebarSearchField\|searchQuery" Pommora/Pommora/ContentView.swift` — zero hits.
- [ ] **Step 5:** Background-builder verify (tests must bootstrap); green. Commit: `refactor(sidebar): remove dead search bar + its top inset`

---

### P4 — Space Folder Layout + Index Schema v12

#### Task 4.1: Spaces become folders with `_space.json`

**Files:** Modify `AtomicIO/NexusPaths.swift`, `Contexts/Space.swift`, `Contexts/SpaceManager.swift`, `Index/IndexBuilder.swift`. Tests: `SpaceFileTests`, `SpaceManagerTests`.

- [ ] **Step 1:** `NexusPaths.swift` — replace `spaceFileURL` (:206-208) with:

```swift
static func spaceFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
    spacesDir(in: nexus).appendingPathComponent(title, isDirectory: true)
}

static func spaceMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
    spaceFolderURL(forTitle: title, in: nexus)
        .appendingPathComponent("_space.json", isDirectory: false)
}
```

- [ ] **Step 2:** `Space.swift` — `load(from:)` (:61-66) derives title from folder: `space.title = url.deletingLastPathComponent().lastPathComponent`; update the path doc comment (:4).
- [ ] **Step 3:** `SpaceManager.swift` — mirror the folder idioms already proven in `ProjectManager` (P1) and `TopicManager`: `loadAll` (:27-56) scans `childFolders` for `_space.json` (skip cosmetic folders); `create` (:71-74) uses `Filesystem.createFolderWithMetadata`; `rename` (:97-119) uses `Filesystem.renameFolder` + save-to-new-metadata with the existing `RenameAtomicityError` rollback; `updateColor` (:156), `updateIcon` (:172), `delete` (:205) use `spaceMetadataURL`/`spaceFolderURL` (+ `moveToTrash(folder)`).
- [ ] **Step 4:** `IndexBuilder.collectContexts` spaces block (:302-313) — switch to the folder scan (same shape as the P1 projects block, sidecar `_space.json`, `tier: 1`).
- [ ] **Step 5:** Tests: `SpaceFileTests` — title derives from folder name; `SpaceManagerTests` (×6 `spaceFileURL` calls :18/:48/:49/:66/:80/:95) — assert `.nexus/spaces/<Title>/_space.json` paths in create/rename/delete/loadExisting fixtures; `NexusPathsTests.swift:160` — replace the `spaceFileURL` path test with `spaceFolderURL`/`spaceMetadataURL` coverage; `RenameAtomicityTests` (×4 `spaceFileURL` :57/:58/:75/:76) — update its Space fixtures to the folder layout; **`RebuildResilienceTests.swift:76`, `IconBackfillTests.swift:35`, `IndexPopulationReproTests.swift:93` (round-4 fix — each calls the deleted `spaceFileURL` to write a Space fixture and would red the P4.1 commit)** — migrate each from `.save(to: spaceFileURL(...))` to `Filesystem.createFolderWithMetadata` (or `.save(to: spaceMetadataURL(...))`); each also constructs `Space(...)`, so they double as folder-layout fixture sites; `IndexBuilderTests` — update any `.space.json` fixture writes (note: it has NO `spaceFileURL` caller — it builds Spaces via `spaceManager.create`).
- [ ] **Step 6:** Background-builder verify; green. Commit: `refactor(contexts): Spaces move to folder + _space.json layout`

#### Task 4.2: Drop `parent_topic_id` — schema v12

**Files:** Modify `Index/IndexSchema.swift`, `Index/PommoraIndex.swift`, `Index/IndexBuilder.swift`, `Index/IndexUpdater.swift`. Tests: index suites (locate via `grep -rln "parent_topic_id" Pommora/PommoraTests`).

- [ ] **Step 1:** `IndexSchema.swift` — `contextsDDL` (:76-84) drops `parent_topic_id TEXT` — it's the LAST column, so remove the trailing comma on the preceding `icon TEXT,` line (not a comma after `parent_topic_id`); delete `idx_contexts_parent_topic` from `indexesDDL` (:138).
- [ ] **Step 2:** `PommoraIndex.swift` — `currentSchemaVersion = 12` (:93) + a dated comment in the version ledger above it: "v12: Contexts Decoupling — contexts.parent_topic_id dropped (free-standing tiers); delete+rebuild on open, no data migration."
- [ ] **Step 3:** `IndexBuilder.swift` — delete `parentTopicID` from `ContextSnapshot` (:72) and from every `ContextSnapshot(...)` constructor call in `collectContexts`; `insertContexts` SQL (:494-498) drops the column + value.
- [ ] **Step 4:** `IndexUpdater.swift` — all three `upsertContext` overloads drop the column from SQL and the trailing `nil` argument.
- [ ] **Step 5:** `grep -rn "parent_topic_id" Pommora/` — MUST return zero hits in Swift sources (docs cleaned in P6). `ConnectionSchemaTests.swift:22` — the literal schema-version assertion (`== 11`) becomes `== 12` (it moves to `== 13` in P5; do NOT delete it — it's the tripwire that catches forgotten bumps).
- [ ] **Step 6:** Background-builder verify; green. Commit: `refactor(index)!: schema v12 — drop contexts.parent_topic_id`

---

### P5 — Space→Area Rename (grep-gated)

**ONE atomic commit + a verification gate — NOT split (third-pass finding).** Three enums with a `space` case are `String`-raw with IMPLICIT raw values — `EntityKind` (IndexQuery.swift:598-600, persisted via state.json refs + looked up through `kindTableMap`), `EntityStateRef`'s kind (NavDropdown, persisted in state.json), and `SidebarToast.ErrorSource` (:26-28 — UI-only; round-4 note: its raw value is NEVER persisted/looked-up, so it does not itself force atomicity — it's renamed in the same commit only for consistency; the atomicity necessity rests on `EntityKind`, whose raw is a live DB lookup key read at IndexQuery.swift:345/347). Renaming `case space`→`case area` silently changes the STRING `"space"`→`"area"`, so a symbols-only commit desyncs `kindTableMap` keys and `RelationTargetKind` tier strings — compiles green, but tier-1 lookups return nil and ~10-20 tests go red until the string side lands. Symbol renames, file renames, raw-value string updates, labels, on-disk tokens, and the schema v13 bump therefore land in a SINGLE commit.

**False-positive exclusion catalog — NEVER touch these patterns:** `spacing:` (HStack/VStack/GridItem), `PUI.Spacing.*`, `PUI.Row.interSpacing`, `whitespace`/`whitespaces`/`.whitespacesAndNewlines`, `@Namespace`/`namespace`, `workspace`, SF Symbol catalog string `"space"` in `Properties/IconPicker/IconCatalog.swift` (the spacebar glyph), SF Symbols `square.stack.3d.up` / `rectangle.3.group`.

#### Task 5.1: The rename — one atomic commit (steps 1–7, build once at the end)

- [ ] **Step 1:** Rename declarations and ALL references (project-wide, tests included): `Space`→`Area`, `SpaceManager`→`AreaManager`, `SpaceColor`→`AreaColor`, `SpaceValidator`→`AreaValidator`, `SpaceRow`→`AreaRow`; methods `createSpace`→`createArea`, `deleteSpace`→`deleteArea` (SidebarConfirmation case + SidebarView), `reorderSpaces`→`reorderAreas`, `resolveSpace`→`resolveArea`; properties `spaces`→`areas` (manager array), `spaceManager`→`areaManager` (env vars), `spaceOrder`→`areaOrder` (NexusState + OrderPersister `setSpaceOrder`→`setAreaOrder` + SpaceManager reader), `lookupSpace`→`lookupArea` (NexusContext + NexusEnvironment closures + PageValidator caller), path helpers `spacesDir`→`areasDir`, `spaceFolderURL`→`areaFolderURL`, `spaceMetadataURL`→`areaMetadataURL`; enum CASES `.space`→`.area` on `EntityKind` (IndexQuery.swift:600), `SelectionTag` (SidebarSelection.swift:158), `SidebarSelection.space`→`.area` (:8), `SidebarSheet.IconTarget.space` (:19), `SidebarSheet.editColor(Space→Area)` (:14), `EntityStateRef` kind, `SidebarConfirmation.deleteSpace`→`deleteArea` — every `case .space:` pattern-match across ~15 files (IndexQuery, EntityRow, EntityStateRef, SidebarSelection, ContentView, NavDropdownButton, BackForwardButtons, ConnectionFileLocator, ConnectionCascade, SidebarDetailView, ContextDisplayResolver, SidebarToast, IconPickerSheet + tests). **Round-4 additions — two files the illustrative ~15-file list never name-matched but the project-wide mandate covers (verified omissions):** (a) `Sidebar/Sheets/ColorPickerSheet.swift` — `let space: Space`→`area: Area` (:4), `init(space:)`→`init(area:)` (:9), `@Environment(SpaceManager.self)` (:6), `@State draft: SpaceColor?` (:7), `SpaceColorPicker(color:)` (:18), `spaceManager.updateColor` (:25), PLUS its two call sites `ColorPickerSheet(space: s)`→`(area: s)` at `SidebarView.swift:115` + `SidebarDetailView.swift:123`; (b) `Validation/NameCollisionValidator.swift:22` `extension Space: NameCollisionCandidate {}`→`extension Area:` (and the `Space` mention in its doc comment :5). **Drive Step 1 by the project-wide grep, NOT the illustrative file list — the list is deliberately incomplete; the build (quirk #3) is the real gate.**
- [ ] **Step 2:** `git mv` file renames: `Space.swift`→`Area.swift`, `SpaceColor.swift`→`AreaColor.swift`, `SpaceManager.swift`→`AreaManager.swift`, `SpaceRow.swift`→`AreaRow.swift`, `Sheets/SpaceColorPicker.swift`→`Sheets/AreaColorPicker.swift`, `Validation/SpaceValidator.swift`→`Validation/AreaValidator.swift`; tests `SpaceFileTests.swift`→`AreaFileTests.swift`, `SpaceManagerTests.swift`→`AreaManagerTests.swift`, `SpaceValidatorTests.swift`→`AreaValidatorTests.swift` — AND their `@Suite`/struct names (`@Suite("AreaManager")` etc. — quirk #1: filters match suite names). `PBXFileSystemSynchronizedRootGroup` absorbs the renames (quirk #2). NOTE: the case renames on `EntityKind` / `EntityStateRef` kind / `ErrorSource` just changed their implicit raw values — steps 3–5 below MUST land in this same commit.
- [ ] **Step 3:** String side of the raw-value change: `kindTableMap` key `"space"`→`"area"` (IndexQuery.swift:13-26); `RelationTargetKind` tier-1 string `"space"`→`"area"` (:20-22); VERIFY no explicit `= "space"` raw assignment remains on any renamed enum; sweep every literal `"space"` comparison/return found by `grep -rn '"space"' Pommora/Pommora --include="*.swift"` (excluding IconCatalog) — this INCLUDES the two hand-written `switch` mappings `kindToString`/`entityKindFromString` (IndexQuery.swift:555-579), whose `return "space"` / `case "space"` literals must become `"area"` (renaming the `case` label alone does NOT touch them — round-4 note).
- [ ] **Step 4:** On-disk tokens: `NexusPaths.areasDir` path component `"spaces"`→`"areas"`; sidecar literal `"_space.json"`→`"_area.json"` (NexusPaths + AreaManager + IndexBuilder + test fixtures).
- [ ] **Step 5:** Labels + UI strings: `TierConfig.swift:32` → `Tier(level: 1, singular: "Area", plural: "Areas", exposed: true)`; `SettingsLabels.swift` — `SidebarSectionLabels.spaces`→`areas`, CodingKey `"spaces"`→`"areas"`, default + decode fallback `"Spaces"`→`"Areas"`; UI literals: `"Delete Space"`→`"Delete Area"` (SidebarView confirmation title), `DefaultTitleResolver.resolve(label: "Space"...)`→`"Area"` (ContextsSection), `"New Space"`→`"New Area"` (AreaRow context menu + ContextsSection createLabel `"Space"`→`"Area"`), `"Tier 1 — Space"`→`"Tier 1 — Area"` (SidebarDetailView:35), EntityRow label `"Space"`→`"Area"` (:73), and the VERIFIED hardcoded tier-1 literals (second-pass census — all confirmed string literals, not settings reads; only the `"Spaces"` string changes, `"Topics"`/`"Projects"` stay): `PropertiesPulldown.swift:198` (`tierRow(label: "Spaces", ids: tier1)`), `PropertyPanel.swift:120/125/130` (ContextChipRow labels — tier-1 line only), `FrontmatterInspector.swift:178` (`tierRow("Spaces", ...)`) + `:182` (`LabeledContent("Spaces", ...)`) — re-grounded after the PagePreview landing; only the `"Spaces"` literals change, `"Topics"`/`"Projects"` stay, `EditPropertyPane.swift:365` (`case 1: return ("square.stack.3d.up", "Spaces")`).
- [ ] **Step 6:** Because the persisted kind strings changed (`EntityKind` in `state.json` recents/pinned, `"area"` in rebuilt `context_links`/`contexts` query paths): bump `currentSchemaVersion = 13` ("v13: Space→Area rename — kind strings; rebuild re-stamps rows"). Stale `state.json` refs with kind `"space"` simply fail resolution and self-heal (verified: `EntityStateRef.typedKind` decodes unknown kinds to nil and callers skip them; recents/pinned are non-critical; greenfield).
- [ ] **Step 7:** Update test fixtures/assertions referencing the old strings: `RelationTargetKindTests.swift:12` (`.contextTier(1)` assertion `"space"`→`"area"`), `ConnectionSchemaTests.swift:22` (schema assertion `== 12` → `== 13`), `UILabelThreadingTests` (`.sidebarSections.spaces`→`.areas` ×5, `"Spaces"`→`"Areas"` ×2), plus `ManagerCreateReturnContractTests`, `RenameAtomicityTests`, `IndexBuilderTests`, `RecentsManagerTests`, `SettingsTests`, `TierConfigTests`, `PropertyColumnBuilderTests`, `EntitiesByTargetGroupedTests` — locate each by `grep -rln 'Space\|"space"' Pommora/PommoraTests`.
- [ ] **Step 8:** Background-builder verify; green; non-zero count. Commit (the ONE rename commit): `refactor(contexts)!: rename Space → Area — symbols, files, kind strings, on-disk tokens, schema v13`

#### Task 5.2: Verification gate

- [ ] **Step 1:** `grep -rn "Space\|space" Pommora/Pommora Pommora/PommoraTests --include="*.swift" | grep -v -E "spacing|whitespace|Namespace|namespace|workspace|interSpacing|square\.stack"` — review EVERY remaining hit; each must be either in the exclusion catalog or justified. Zero entity-meaning hits remain. (Round-4 note: stale `"space"`/`moveProject` mentions inside COMMENTS — e.g. `TierRelationsEmitTests.swift:105/169`, `PageContentManager+CRUD.swift:487` — are cosmetic, not entity-meaning; fix inline here or sweep in P6.)
- [ ] **Step 2:** Full `PommoraTests` background-builder run; record final count. Commit only if Step 1 output is clean (fold any stragglers into this commit): `chore(contexts): Space→Area rename verification sweep`

---

### P6 — Docs Rewrite (spec-voice, branch end)

Write every passage as locked present-tense spec ("Projects are free-standing tier-3 contexts"), never as change narrative. Use the docs-audit-skill before editing.

- [ ] **Step 1:** `Features/Contexts.md` — full rewrite: three free-standing tiers (Areas/Topics/Projects), folder + sidecar layout (`_area.json`/`_topic.json`/`_project.json`), bare schemas, no parents/containment/promotion/tier-skip; cross-layer `tier1/2/3` section survives as-is; deferred-relations note pointing at the future design pass.
- [ ] **Step 2:** `Features/Sidebar.md` — context area: one headerless section, three `square.grid.2x2` disclosure rows (expand/collapse only, context-menu + hover-+ creation), flat leaf children; update the layout mock + creation-affordance table; selection-language section unchanged.
- [ ] **Step 3:** `PommoraPRD.md` — Domain Model + Storage Model trees (`.nexus//areas|topics|projects//<Title>//_*.json`), SQLite schema (contexts without `parent_topic_id`, v13), terminology Spaces→Areas.
- [ ] **Step 4:** `Features/Architecture.md` — nexus layout tree + manager table (AreaManager/TopicManager/ProjectManager).
- [ ] **Step 5:** `Features/Spaces.md` → rename `Features/Areas.md`, rewrite to the bare-entity spec. `Features/Properties.md` — clarify tier links are the sole context connections. `Guidelines/CRUD-Patterns.md` + `Guidelines/Symbols.md` + `Guidelines/Design.md` — mechanical Area rename in examples.
- [ ] **Step 6:** `Guidelines/Paradigm-Decisions.md` — new entry superseding the ParadigmV2 containment decision: free-standing tiers, relation layer deferred, Space→Area. `History.md` — one concise ship entry. Project `CLAUDE.md` — overview line: "Areas (1) / Topics (2) / Projects (3)". `Framework.md` — roadmap touch-ups. `Planning//README.md` — move spec+plan to the shipped state per its convention.
- [ ] **Step 7:** Commit: `docs(contexts): spec-voice rewrite — free-standing tiers, Areas rename (decoupling shipped)`

---

### Plan Self-Review Record

- **Spec coverage:** decoupling → P1; relation reset → P1+P2; folders-with-sidecars (all three tiers) → P1 (projects), P4 (areas), topics already folders; blocks kept → entity rewrites preserve `blocks`; sibling managers → P1; sidebar disclosure rows → P3; no migration → none planned; docs → P6; Area rename → P5 (user addition post-spec — supersedes the spec's "Spaces" naming; P6 docs absorb it).
- **Known judgment calls baked in:** Projects tier-row label reuses the EXISTING `labels.project.plural` — no new settings key (strip mandate; label-source unification deferred to the settings-UI work); index column drop deferred to P4 so P1–P3 write `nil` into a still-existing column; kind-string rename forces schema v13 in P5; validator transition is a staged overload (bare overload added in Task 1.2, legacy signature deleted in Task 1.3 with its last callers) — zero throwaway code.
- **Deliberate deviations from current code:** none — all idioms (rollback, defensive sync, stub-and-edit, OrderResolver) are copied from verified sources.
- **Fourth pass — round 4 (applied; NOT yet certified).** Three independent lenses (anchor/API grounding · commit-boundary/coverage · downstream-ripple), each grounded against the post-PagePreview-landing tree. Found + folded 4 blockers + 2 majors the prior three passes missed: **(B1)** P1.3 deleted `updateTopicParents` while its sole caller `EditTopicParentsSheet.swift:57` survives to P2.1 → red commit; deletion moved to P2.2 Step 3 (same commit that strips `Topic.parents`). **(B2)** P4.1 deletes `spaceFileURL` but missed three test callers (`RebuildResilienceTests:76`, `IconBackfillTests:35`, `IndexPopulationReproTests:93`) → added to Step 5. **(B3/B4)** P5 rename never name-matched `ColorPickerSheet.swift` (Space-typed sheet + 2 call sites) or `NameCollisionValidator.swift:22` (`extension Space: NameCollisionCandidate`) → added to Task 5.1 Step 1, now explicitly grep-driven. **(M1)** the real `SidebarLookupBundle(` set is `SidebarView:71` + `ContentView:93/:170`, NOT "BackForwardButtons/NavDropdownButton" (those only RECEIVE a bundle) → corrected in Task 1.3 Files + Step 10. **(M2)** `TopicManager(...)` is inline-constructed at ~8 test sites, NOT a shared helper (corrects the third-pass record's overstatement) → P2.2 Step 3 reworded. Minors folded: `ErrorSource` carries no persisted raw (atomicity rests on `EntityKind` alone); the `"space"` string surface includes the hand-written `kindToString`/`entityKindFromString` switches (named in Step 3); `AppGlobals` must NOT gain a `projectManager` slot (dead code); v12 comma precision; cosmetic stale-comment note. Confirmed clean by all three lenses (no change): the staged validator overload, type/name consistency, full spec coverage, env-injection mechanics, the TopicManager deletion ripple. The two PROVISIONAL anchor drifts were re-grounded once the parallel session landed: `ContentView.swift` `SidebarSearchField` :382→:380, `FrontmatterInspector.swift` tier-1 literals :139-145→:178/:182. The parallel-session gate is now CLEARED (only `PagePreviewWindow.swift` remains, not a plan dependency).
- **Fifth pass — round 5 (CLEAN → review-certified).** Two focused lenses on the post-fold plan: (1) a generalized sweep of the B1 bug class — for EVERY deleted symbol, every caller confirmed covered by the same-or-earlier commit across all 12 commits → **no surviving-caller bugs**; (2) fold-correctness — all six round-4 folds verified correct, complete, and internally consistent, both cross-consistency checks pass. No new findings. Per Review-Discipline, a round came back genuinely clean → **the plan is REVIEW-CERTIFIED** (rounds 1–3 prior + round 4 folded + round 5 clean). Standing execution-time check remains: the build (quirk #3) is the final anchor verifier; re-confirm ContentView/SidebarView grep anchors cheaply before P1/P3.
- **Third ("bulletproof") pass — commit-boundary simulation + test census (applied):** P5's symbols-vs-strings commit split was a REAL intermediate breakage — `EntityKind`/`EntityStateRef`-kind/`ErrorSource` are String-raw with implicit raw values, so the case rename alone desyncs `kindTableMap`/`RelationTargetKind` (green compile, red behavior); P5 is now ONE atomic commit + gate. Test census named every breaking test site per phase (18 files), now enumerated in the task test-steps — including the `ConnectionSchemaTests` literal version assertion (bumps 11→12→13, kept as the tripwire) and the `TopicManagerTests`/`TopicValidatorTests` shared helpers (one edit fixes all call sites). Explicit injection-verification added to P1 Step 9 (quirk #15 SIGTRAPs at runtime, not compile). SidebarToast wiring expanded to its four required points (env var, ErrorSource case, capture, dismiss). One simulator claim REJECTED as false positive: "Task 1.3 Step 10 lacks the resolveProject rewrite" — the full body has been in Step 10 since the first draft.
- **Second adversarial pass (applied):** every API signature in the plan's snippets verified against declarations (`Filesystem.*`, `OrderResolver.resolve`, `RenameAtomicityError`, `AtomicJSON`, `CreateWithInlineEdit.run`, `DefaultTitleResolver`, `ULID.generate`, `EntityKind` implicit raw values — all OK). Added findings: `IconPickerSheet.swift:68` project-icon dispatch (P1 Step 15), `SidebarToast` pendingError aggregation (P1 Step 16), `SidebarDetailView.swift:121` second `editTopicParents` sheet site (P2 Task 2.1 Step 3), hardcoded tier-1 literals in PropertiesPulldown/PropertyPanel/FrontmatterInspector (P5 Task 5.1 Step 5). Removed as scope creep: `sidebarSections.projects` settings key, `.help()` tooltip, the Task 1.2 throwaway validator stub. Verified safe (no plan change needed): ConnectionFileLocator/ConnectionCascade context cases are no-ops; ComponentLibraryView has no breaking constructors; PageValidator's tier lookups ride the rewired NexusContext closures; EntityStateRef decodes unknown kinds to `typedKind == nil` and skips (the P5 self-heal claim is real).

### Execution Log (subagent-driven, on `main`)

Baseline: **987 tests green** at `main` HEAD (v0.4.0) pre-execution.

- **Task 1.1 ✅ `933d4fa`** — additive plumbing (NexusPaths `projectsDir`/`projectFolderURL`/`projectMetadataURL`, `NexusState.projectOrder`, flat `OrderPersister.setProjectOrder(_:in:)`, 2 tests). Spec review ✅ (41 lines, additive-only, nothing extra). Quality review ✅ APPROVED (2 cosmetic MARK suggestions, non-blocking). Tests: **989 green** (+2). **Plan re-assessment:** the flat overload landed at OrderPersister :39-43, shifting the topic-sidecar overload to :47-52 → corrected Task 1.3 Step 5's anchor (was :39-46, which now points at the KEEP target). Delete-by-signature, not by line.
- **Task 1.2 ✅ `32615a0`** — `ProjectManager` (clone of `SpaceManager`, folder idiom) + bare `ProjectValidator.validate(title:existing:excluding:)` overload (legacy 6-param untouched) + 5 `ProjectManager` tests; NOT wired in (additive/unused). Spec review ✅ (only 3 files; legacy validate present; not wired; loadAll-fixture test correctly deferred). Quality review ✅ APPROVED (rollback/index-sync/order-persistence/Swift-6 all match siblings); 2 minor cleanups applied (dead `ULID.generate()` hoist removed from the `create` test; `loadAll` comment corrected). Tests: **993 green, 0 failures** (all 5 new pass; ±1 swift-testing distinct-case counting variance vs naive arithmetic — no test lost, changes were additive-only). **Plan re-assessment:** `loadAll` carries a workaround `project.title = folder.lastPathComponent` (current `Project.load` titles from filename) → Task 1.3 Step 4 must REMOVE it once Step 1 rewrites `Project.load`. (Build was briefly blocked mid-task by a parallel-session compile error in `NativeTextView+DragSelectBoost.swift`; Nathan fixed it; verification then ran clean.)
- **Collision pause + checkpoint `9b70966`** — before Task 1.3, Nathan's parallel preview-window session had `ContentView.swift` + `SidebarView.swift` (which 1.3 must rewrite) uncommitted. Per his instruction, committed his cohesive preview work as a WIP checkpoint (`9b70966`, compile-gated green) to unblock; anchors then re-verified against the landed files (bundle sites still `SidebarView:71`/`ContentView:93`/`:170`).
- **Task 1.3 ✅ `0239710`** — the pivot: bare `Project` entity, `Project.load` titles-from-folder, all project CRUD/promotion/`projectsByParent`/`Topic.projectOrder` deleted, `ProjectManager` wired into `NexusEnvironment` (injection confirmed, no SIGTRAP), index scans free-standing `projects/`, UI compile-closure across SidebarSelection/TopicRow/ProjectRow/SidebarView/SidebarConfirmation/IconPickerSheet/SidebarToast. −825/+197 over 26 files. Spec ✅ (all 19 steps, `updateTopicParents`+`Topic.parents` correctly retained for P2). Tests **995 green** (Task 1.3's 9 owned suites all bootstrapped + green; the 1 failure `PreviewWindowRestrictionTests/tamesPanelFocus` is Nathan's uncommitted preview work, NOT 1.3). Quality ✅ APPROVED. **Carry-forward:** `ProjectRow`/`ProjectManager.reorder/create` have no UI caller until P3 re-mounts them (sanctioned quirk #7 stub-and-replace).
- **Task 2.1 ✅ `b9c5490`** — deleted topic-parents UI (EditTopicParentsSheet file, ParentSpaceTags, Edit-Parents button, both trailing closures, detail-pane `parentSpaceNames`→"Tier 2 — Topic", both `.sheet` switch cases) + the orphaned `@Environment(SettingsManager.self)`/`SpaceManager` env vars in TopicRow/SidebarDetailView. Spec+quality ✅, grep-clean (4 symbols→0). `Topic.parents`/`TopicValidator`/`updateTopicParents` correctly left for 2.2. Tests 995 green, no regression.
- **Task 2.2 ✅ `b689f58`** — Topic bare tier-2: removed `parents` field (all Codable touch-points), `TopicValidator` parents/context params + `parentNotFound`, `updateTopicParents`, and `TopicManager.contextProvider` (stored prop + init param; `PageContentManager.contextProvider` correctly retained); `IndexUpdater` passes nil parent; 16 test files fixed incl. 8 inline `TopicManager(...)` constructions (grep-driven, not a shared helper — round-4 M1 held). Spec+quality ✅. Tests **993 green, fully green** (Nathan's preview session converged mid-run — the prior `tamesPanelFocus` parallel failure is gone). Tidied a stale `TopicRow` doc comment (amend).
- **Task 3.1 ✅ `0f68a6a`** — sidebar `ContextsSection`: ONE headerless Section + three `square.grid.2x2` `TierDisclosureRow`s (Spaces/Topics/Projects — expand/collapse only, hover-"+" + context-menu creation, flat-leaf children). `SpacesSection`/`TopicsSection` structs deleted; `ProjectRow` re-mounted (resolves the 1.3 carry-forward — Projects now visible in the sidebar again); Projects label reuses `labels.project.plural` (no new settings key). Spec+quality ✅ (homogeneous Section, tier rows untagged, row-level `SelectionChrome` — mirrors VaultsSection). **Quirk #8 gate PASSED: 994 tests BOOTSTRAPPED + green, host app boots clean, no `recursivelyDiffRows` regression.**
- **Task 3.2 ✅ `0e3a990`** — removed the dead sidebar search bar (`SidebarSearchField` struct + `searchQuery` state + the `.safeAreaInset` top inset; 3 deletions in `ContentView.swift`, grep-clean). Spec+quality ✅. Tests 994 green, bootstrap confirmed. **P3 functionally complete** — post-functional UIX review of the working sidebar is the Review-Discipline gate before this phase is "done." (Nathan's preview session landed at `ff16ee8` during P3.)
- **P3 UX fix ✅ `f5e6abb`** — post-functional review: Nathan approved the sidebar ("looks good") and asked for a **"Contexts" header** above the three tier rows. Added via `Section(isExpanded: $expanded) { …3 TierDisclosureRows… } header: { Text("Contexts").foregroundStyle(.secondary) }` — mirrors VaultsSection's proven collapsible shape (quirk #8 safe); no section-level "+" (each tier keeps its own). Verified green + bootstrap. **→ P6 NOTE:** the spec's "one headerless Section" is SUPERSEDED — `Sidebar.md` must describe the "Contexts" header.
- **Flaky-test fix ✅ `ce80b4b`** (out-of-plan, Nathan-approved) — normalized 8 PRE-EXISTING intermittent `/private`-symlink path assertions in `AgendaTaskManagerTests`/`AgendaEventManagerTests`/`NexusPathsTests`/`NexusAdopterTests` via `.resolvingSymlinksInPath()` (macOS `/var`→`/private/var`; unrelated to the decoupling — surfaced during P3 verification). Cleans the baseline before P4 touches `NexusPaths`.
- **Task 4.1 ✅ `1fcce4f`** — Spaces → folder + `_space.json` layout (mirrors Project/Topic): `NexusPaths` `spaceFolderURL`/`spaceMetadataURL`, `Space.load` titles-from-folder, `SpaceManager` folder CRUD + `RenameAtomicityError` rollback, `IndexBuilder` folder scan. 13 fixtures across 7 test files migrated; grep-clean (`spaceFileURL`/`.space.json` → 0). Spec+quality ✅ (rollback matches `ProjectManager`; `SpaceColor`/ordering unchanged; `parent_topic_id` retained for 4.2; the ce80b4b `/private` normalization preserved). Tests 993 green, bootstrap confirmed.
