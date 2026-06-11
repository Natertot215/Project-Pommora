import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPageSets

/// How `deletePageSet` treats the Set's member Pages.
enum SetDeleteMode {
    /// Dissolve the Set: every `.md` Page moves up into the parent
    /// PageCollection folder, then the (page-empty) Set folder is trashed.
    case setOnly
    /// Trash the whole Set folder, Pages included.
    case withPages
}

@MainActor
@Observable
final class PageSetManager {
    private(set) var pageSetsByCollection: [String: [PageSet]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Injected by NexusEnvironment alongside the other managers. Nil until
    /// wired; CRUD methods call it post-commit as a best-effort non-fatal
    /// write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func pageSets(in collection: PageCollection) -> [PageSet] {
        pageSetsByCollection[collection.id] ?? []
    }

    // MARK: - Load

    /// Discovers PageSets as DIRECT child folders of each PageCollection.
    /// A sub-folder inside a PageCollection can only be a PageSet, so a
    /// missing `_pageset.json` (folder created by hand in Finder, or
    /// pre-existing before adoption) is healed with a fresh sidecar in place,
    /// and a drifted `collection_id` is re-pointed at the containing
    /// Collection — both mirroring PageTypeManager's heal-on-load.
    func loadAll(collections: [PageCollection], filter: FolderFilter = .empty) async {
        do {
            var loaded: [String: [PageSet]] = [:]
            for collection in collections {
                let sets = try Filesystem.childFolders(of: collection.folderURL, folderFilter: filter)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> PageSet? in
                        let metaURL = sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                        if !Filesystem.fileExists(at: metaURL) {
                            let fresh = PageSet(
                                id: ULID.generate(),
                                collectionID: collection.id,
                                title: sub.lastPathComponent,
                                folderURL: sub,
                                modifiedAt: Date()
                            )
                            try? Filesystem.writeMetadataIntoExistingFolder(
                                metadataURL: metaURL, metadata: fresh
                            )
                        }
                        guard var set = try? PageSet.load(from: metaURL) else { return nil }
                        // Heal a drifted `collection_id`: the containing folder is
                        // authoritative, so a Set inside this Collection's folder
                        // belongs to it. Re-point + re-save in place; idempotent.
                        if set.collectionID != collection.id {
                            set.collectionID = collection.id
                            try? set.save(to: metaURL)
                        }
                        return set
                    }
                loaded[collection.id] = OrderResolver.resolve(
                    sets,
                    persistedOrder: collection.setOrder,
                    titleKeyPath: \PageSet.title
                )
            }

            self.pageSetsByCollection = loaded
            self.pendingError = nil

            // Defensive index sync (quirk #14): Sets arriving outside CRUD
            // (Finder-created folders, adoption) must land in the index so a
            // subsequent page upsert carrying their id doesn't FK-fail.
            // INSERT OR REPLACE makes this idempotent; failures swallowed —
            // the index is regeneratable, no user data lost.
            if let updater = indexUpdater {
                for sets in loaded.values {
                    for set in sets {
                        try? updater.upsertPageSet(set)
                    }
                }
            }
        } catch {
            self.pageSetsByCollection = [:]
            self.pendingError = error
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createPageSet(name: String, in collection: PageCollection) async throws -> PageSet {
        do {
            let existing = pageSetsByCollection[collection.id] ?? []
            try PageSetValidator.validate(title: name, existingInCollection: existing)

            let folder = collection.folderURL.appendingPathComponent(name, isDirectory: true)
            let now = Date()
            let set = PageSet(
                id: ULID.generate(),
                collectionID: collection.id,
                title: name,
                folderURL: folder,
                modifiedAt: now
            )
            let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: metaURL, metadata: set
            )

            if let updater = indexUpdater {
                do { try updater.upsertPageSet(set) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(set)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.setOrder,
                titleKeyPath: \PageSet.title
            )
            pageSetsByCollection[collection.id] = arr
            return set
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageSet(_ set: PageSet, to newName: String) async throws {
        do {
            let existing = pageSetsByCollection[set.collectionID] ?? []
            try PageSetValidator.validate(
                title: newName, existingInCollection: existing, excluding: set
            )

            let newURL = set.folderURL.deletingLastPathComponent()
                .appendingPathComponent(newName, isDirectory: true)
            try Filesystem.renameFolder(from: set.folderURL, to: newURL)

            // Copy-mutate so a rename only touches what a rename legitimately
            // changes (title / folderURL / modifiedAt) and preserves every
            // other field — icon, pageOrder, schemaVersion — automatically.
            let now = Date()
            var updated = set
            updated.title = newName
            updated.folderURL = newURL
            updated.modifiedAt = now
            let metaURL = newURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            do {
                try updated.save(to: metaURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFolder(from: newURL, to: set.folderURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertPageSet(updated) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == set.id }) {
                arr[i] = updated
                // Re-resolve against the parent Collection's persisted setOrder
                // (read from its sidecar — the live PageCollection value lives
                // on PageTypeManager, not here).
                let parentMetaURL = newURL.deletingLastPathComponent()
                    .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: (try? PageCollection.load(from: parentMetaURL))?.setOrder,
                    titleKeyPath: \PageSet.title
                )
            }
            pageSetsByCollection[set.collectionID] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updatePageSetIcon(_ set: PageSet, to icon: String?) async throws {
        do {
            var updated = set
            updated.icon = icon
            updated.modifiedAt = Date()
            let metaURL = set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            try updated.save(to: metaURL)
            if let updater = indexUpdater {
                do { try updater.upsertPageSet(updated) } catch { self.pendingError = error }
            }
            var arr = pageSetsByCollection[set.collectionID] ?? []
            if let i = arr.firstIndex(where: { $0.id == set.id }) {
                arr[i] = updated
            }
            pageSetsByCollection[set.collectionID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePageSet(_ set: PageSet, mode: SetDeleteMode) async throws {
        do {
            switch mode {
            case .withPages:
                break
            case .setOnly:
                try rehomePages(of: set)
            }
            try Filesystem.moveToTrash(set.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageSet(id: set.id) } catch { self.pendingError = error }
            }
            var arr = pageSetsByCollection[set.collectionID] ?? []
            arr.removeAll { $0.id == set.id }
            pageSetsByCollection[set.collectionID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Moves every direct-child `.md` Page of `set` up into the parent
    /// PageCollection folder. Collision-safe: ALL destination names are
    /// checked before anything moves, so a duplicate-title throw leaves the
    /// Set untouched. Each moved Page is re-indexed under the Collection
    /// (page_set_id → nil); the sidecar stays behind for the trash move.
    private func rehomePages(of set: PageSet) throws {
        let collectionFolder = set.folderURL.deletingLastPathComponent()
        let pageFiles = try Filesystem.children(of: set.folderURL) { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
        }

        // Check every destination FIRST — throw before moving anything.
        for url in pageFiles {
            let dest = collectionFolder.appendingPathComponent(url.lastPathComponent)
            try Filesystem.guardNoFile(at: dest, else: PageSetValidator.ValidationError.duplicateTitle)
        }

        // Parent ids for the re-index. Best-effort: if the Collection sidecar
        // can't be read, the moves still happen (filesystem is canonical) and
        // the index converges on the next rebuild.
        let parentMetaURL = collectionFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let parentCollection = try? PageCollection.load(from: parentMetaURL)
        let nexusRoot = nexus.rootURL

        for url in pageFiles {
            let dest = collectionFolder.appendingPathComponent(url.lastPathComponent)
            try Filesystem.renameFile(from: url, to: dest)
            if let updater = indexUpdater,
                let parent = parentCollection,
                let pf = try? PageFile.loadLenient(from: dest, nexusRoot: nexusRoot)
            {
                let meta = PageMeta(
                    id: pf.frontmatter.id, title: pf.title, url: dest, frontmatter: pf.frontmatter
                )
                try? updater.upsertPage(
                    meta, pageTypeID: parent.typeID, pageCollectionID: parent.id, pageSetID: nil
                )
            }
        }
    }

    // MARK: - Reorder

    /// Reorders PageSets within `collection`. Matches the SwiftUI
    /// `.onMove(perform:)` signature. New ID order persists to the parent
    /// PageCollection's `_pagecollection.json` sidecar.
    func reorderPageSets(in collection: PageCollection, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = pageSetsByCollection[collection.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pageSetsByCollection[collection.id] = arr
        do {
            try OrderPersister.setPageSetOrder(arr.map(\.id), in: collection)
        } catch {
            self.pendingError = error
        }
    }

    // MARK: - Folder-URL rebuild

    /// Re-derives each cached Set's `folderURL` from the (renamed) parent
    /// Collection's folder. Invoked via PageTypeManager's
    /// `onCollectionFolderChanged` hook after a Collection or Page Type
    /// rename moves the folders on disk (the Sets travel with their parent;
    /// only the cached URLs go stale). Pages' URLs are handled separately.
    func rebuildFolderURLs(for collection: PageCollection) {
        guard let sets = pageSetsByCollection[collection.id] else { return }
        pageSetsByCollection[collection.id] = sets.map { set in
            var updated = set
            updated.folderURL = collection.folderURL.appendingPathComponent(set.title, isDirectory: true)
            return updated
        }
    }
}
