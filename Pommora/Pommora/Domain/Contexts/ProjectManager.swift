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
    /// `upsertContext(_:)`.
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
                guard Filesystem.fileExists(at: metaURL) else { continue }
                guard let project = try? Project.load(from: metaURL) else { continue }
                loaded.append(project)
            }
            self.projects = OrderResolver.resolve(
                loaded,
                persistedOrder: readPersistedProjectOrder(),
                titleKeyPath: \Project.title
            )
            self.pendingError = nil
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

    /// Reorders Projects in response to a sidebar drag. Matches SwiftUI
    /// `.onMove(perform:)`. New full ID order persists to `.nexus/state.json`.
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
