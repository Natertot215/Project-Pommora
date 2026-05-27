import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderSpaces

@MainActor
@Observable
final class SpaceManager {
    private(set) var spaces: [Space] = []
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadAll() async {
        do {
            let dir = NexusPaths.spacesDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let files = try Filesystem.children(of: dir) { url in
                url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "space"
            }
            let loaded = files.compactMap { try? Space.load(from: $0) }
            self.spaces = OrderResolver.resolve(
                loaded,
                persistedOrder: readPersistedSpaceOrder(),
                titleKeyPath: \Space.title
            )
            self.pendingError = nil
        } catch {
            self.spaces = []
            self.pendingError = error
        }
    }

    @discardableResult
    func create(name: String, color: SpaceColor?, icon: String?) async throws -> Space {
        do {
            try SpaceValidator.validate(title: name, existing: spaces)

            let space = Space(
                id: ULID.generate(),
                title: name,
                color: color,
                icon: icon,
                blocks: [],
                modifiedAt: Date()
            )
            let dir = NexusPaths.spacesDir(in: nexus)
            try NexusPaths.ensureDirectoryExists(dir)
            let url = NexusPaths.spaceFileURL(forTitle: name, in: nexus)
            try space.save(to: url)

            spaces.append(space)
            spaces = OrderResolver.resolve(
                spaces,
                persistedOrder: readPersistedSpaceOrder(),
                titleKeyPath: \Space.title
            )
            return space
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func rename(_ space: Space, to newName: String) async throws {
        do {
            try SpaceValidator.validate(title: newName, existing: spaces, excluding: space)

            let oldURL = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
            let newURL = NexusPaths.spaceFileURL(forTitle: newName, in: nexus)

            var updated = space
            updated.title = newName
            updated.modifiedAt = Date()

            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                // Roll back the file rename so the on-disk name matches the
                // (unchanged) in-memory state. If the rollback ALSO fails the
                // on-disk state is inconsistent — surface that explicitly.
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let i = spaces.firstIndex(where: { $0.id == space.id }) {
                spaces[i] = updated
                spaces = OrderResolver.resolve(
                    spaces,
                    persistedOrder: readPersistedSpaceOrder(),
                    titleKeyPath: \Space.title
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

    /// Reads the persisted Space sibling order from `.nexus/state.json`. Returns
    /// nil if no state.json exists or no `spaceOrder` has been recorded — the
    /// resolver falls back to alphabetic in that case.
    private func readPersistedSpaceOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.spaceOrder
    }

    func updateColor(_ space: Space, to color: SpaceColor?) async throws {
        do {
            var updated = space
            updated.color = color
            updated.modifiedAt = Date()
            let url = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
            try updated.save(to: url)
            if let i = spaces.firstIndex(where: { $0.id == space.id }) {
                spaces[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func updateIcon(_ space: Space, to icon: String?) async throws {
        do {
            var updated = space
            updated.icon = icon
            updated.modifiedAt = Date()
            let url = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
            try updated.save(to: url)
            if let i = spaces.firstIndex(where: { $0.id == space.id }) {
                spaces[i] = updated
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Spaces in response to a sidebar drag (v0.2.8.0). Matches the
    /// SwiftUI `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
    func reorderSpaces(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = spaces
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != spaces else { return }
        spaces = arr
        do {
            try OrderPersister.setSpaceOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    func delete(_ space: Space) async throws {
        do {
            let url = NexusPaths.spaceFileURL(forTitle: space.title, in: nexus)
            try Filesystem.moveToTrash(url, in: nexus)
            spaces.removeAll { $0.id == space.id }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
