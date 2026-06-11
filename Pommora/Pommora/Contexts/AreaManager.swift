import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderAreas

@MainActor
@Observable
final class AreaManager {
    private(set) var areas: [Area] = []
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    /// Injected by ContentView.constructManagers. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    /// Areas index into `contexts` as tier 1 via `upsertContext(_:)` — without this,
    /// `IndexQuery.entitiesByContextTarget(.contextTier(1))` (the inline tier picker source)
    /// never sees Areas created/edited since the last full IndexBuilder rebuild.
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.areasDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            var loaded: [Area] = []
            let folders = try Filesystem.childFolders(of: dir)
            for folder in folders {
                let metaURL = folder.appendingPathComponent("_area.json")
                guard Filesystem.fileExists(at: metaURL) else { continue }
                guard let area = try? Area.load(from: metaURL) else { continue }
                loaded.append(area)
            }
            self.areas = OrderResolver.resolve(
                loaded,
                persistedOrder: readPersistedAreaOrder(),
                titleKeyPath: \Area.title
            )
            self.pendingError = nil

            // Defensive index sync (quirk #15). Areas arriving outside CRUD
            // (adopted / externally-added / pre-existing folders) must land in
            // the `contexts` table so the tier-1 picker can surface them.
            // INSERT OR REPLACE is idempotent; failures swallowed (index is
            // regeneratable, no user data lost).
            if let updater = indexUpdater {
                for area in self.areas {
                    try? updater.upsertContext(area)
                }
            }
        } catch {
            self.areas = []
            self.pendingError = error
        }
    }

    @discardableResult
    func create(name: String, color: AreaColor?, icon: String?) async throws -> Area {
        do {
            try AreaValidator.validate(title: name, existing: areas)

            let area = Area(
                id: ULID.generate(),
                title: name,
                color: color,
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.areaFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.areaMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: area)

            if let updater = indexUpdater {
                do { try updater.upsertContext(area) } catch { self.pendingError = error }
            }

            areas.append(area)
            areas = OrderResolver.resolve(
                areas,
                persistedOrder: readPersistedAreaOrder(),
                titleKeyPath: \Area.title
            )
            return area
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func rename(_ area: Area, to newName: String) async throws {
        do {
            try AreaValidator.validate(title: newName, existing: areas, excluding: area)

            let oldFolder = NexusPaths.areaFolderURL(forTitle: area.title, in: nexus)
            let newFolder = NexusPaths.areaFolderURL(forTitle: newName, in: nexus)

            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = area
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.areaMetadataURL(forTitle: newName, in: nexus)
            do {
                try updated.save(to: newMeta)
            } catch let saveError {
                // Roll back the folder rename so the on-disk name matches the
                // (unchanged) in-memory state. If the rollback ALSO fails the
                // on-disk state is inconsistent — surface that explicitly.
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

            if let i = areas.firstIndex(where: { $0.id == area.id }) {
                areas[i] = updated
                areas = OrderResolver.resolve(
                    areas,
                    persistedOrder: readPersistedAreaOrder(),
                    titleKeyPath: \Area.title
                )
            }
        } catch {
            // RenameAtomicityError already sets pendingError; don't double-wrap.
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    /// Reads the persisted Area sibling order from `.nexus/state.json`. Returns
    /// nil if no state.json exists or no `areaOrder` has been recorded — the
    /// resolver falls back to alphabetic in that case.
    private func readPersistedAreaOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.areaOrder
    }

    func updateColor(_ area: Area, to color: AreaColor?) async throws {
        do {
            var updated = area
            updated.color = color
            updated.modifiedAt = Date()
            let meta = NexusPaths.areaMetadataURL(forTitle: area.title, in: nexus)
            try updated.save(to: meta)
            if let i = areas.firstIndex(where: { $0.id == area.id }) {
                areas[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func updateIcon(_ area: Area, to icon: String?) async throws {
        do {
            var updated = area
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.areaMetadataURL(forTitle: area.title, in: nexus)
            try updated.save(to: meta)
            // `icon` is an indexed `contexts` column — re-upsert so the tier
            // picker (which displays icon + title) reflects the change.
            if let updater = indexUpdater {
                do { try updater.upsertContext(updated) } catch { self.pendingError = error }
            }
            if let i = areas.firstIndex(where: { $0.id == area.id }) {
                areas[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Areas in response to a sidebar drag (v0.2.8.0). Matches the
    /// SwiftUI `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderAreas(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = areas
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != areas else { return }
        areas = arr
        do {
            try OrderPersister.setAreaOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    func delete(_ area: Area) async throws {
        do {
            let folder = NexusPaths.areaFolderURL(forTitle: area.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            // Drop the stale `contexts` row (closes the stale-index-row-on-delete gap).
            if let updater = indexUpdater {
                do { try updater.deleteContext(id: area.id) } catch { self.pendingError = error }
            }
            areas.removeAll { $0.id == area.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
