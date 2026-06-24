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
    /// Depth-1: Collections keyed by their parent PageCollection id.
    private(set) var depthOneSetsByCollection: [String: [PageSet]] = [:]
    /// Depth-2+: Sets keyed by their parent PageSet id.
    private(set) var childSetsByParentSet: [String: [PageSet]] = [:]
    var pendingError: (any Error)?

    /// IDs of all top-tier PageCollections. A PageSet is view-eligible iff
    /// `topTierIDs.contains(set.parentID)` — O(1) at render time.
    private(set) var topTierIDs: Set<String> = []

    private let nexus: Nexus

    /// Injected by NexusEnvironment alongside the other managers. Nil until
    /// wired; CRUD methods call it post-commit as a best-effort non-fatal
    /// write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    /// Injected by NexusEnvironment so depth-demotion moves can prune stale
    /// `.collection` Recents entries. Nil in test harnesses that don't wire
    /// navigation; pruning is a best-effort advisory (filesystem is canonical).
    var recentsManager: RecentsManager?

    /// Closure supplying the current PageCollection array. Wired by NexusEnvironment
    /// so Collection reorders and renames can read the parent type's `collectionOrder`.
    @ObservationIgnored var pageCollectionProvider: (() -> [PageCollection])?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    private func refreshTopTierIDs(from types: [PageCollection]) {
        topTierIDs = Set(types.map(\.id))
    }

    func pageCollections(in pageCollection: PageCollection) -> [PageSet] {
        depthOneSetsByCollection[pageCollection.id] ?? []
    }

    func pageSets(in collection: PageSet) -> [PageSet] {
        childSetsByParentSet[collection.id] ?? []
    }

    // MARK: - Load

    /// Discovers PageCollections as direct children of each PageCollection folder,
    /// then recurses arbitrarily deep into each Set's child folders.
    /// Missing sidecars are healed in place; drifted parent IDs are re-pointed.
    func loadAll(types: [PageCollection], filter: FolderFilter = .empty) async {
        do {
            refreshTopTierIDs(from: types)

            var loadedCols: [String: [PageSet]] = [:]
            var loadedSets: [String: [PageSet]] = [:]
            var seenCollectionIDs: Set<String> = []
            var seenSetIDs: Set<String> = []

            for pageCollection in types {
                let typeFolder = NexusPaths.collectionFolderURL(forTitle: pageCollection.title, in: nexus)
                let parentPropertyIDs = pageCollection.properties.map(\.id)

                var cols = try Filesystem.childFolders(of: typeFolder, folderFilter: filter)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> PageSet? in
                        let collMetaURL = sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                        if !Filesystem.fileExists(at: collMetaURL) {
                            let fresh = PageSet(
                                id: ULID.generate(),
                                parentID: pageCollection.id,
                                title: sub.lastPathComponent,
                                folderURL: sub,
                                modifiedAt: Date()
                            )
                            try? Filesystem.writeMetadataIntoExistingFolder(
                                metadataURL: collMetaURL, metadata: fresh
                            )
                        }
                        guard var collection = try? PageSet.load(from: collMetaURL) else {
                            return nil
                        }
                        if collection.parentID != pageCollection.id {
                            collection.parentID = pageCollection.id
                            try? collection.save(to: collMetaURL)
                        }
                        if collection.views.isEmpty && topTierIDs.contains(collection.parentID) {
                            collection.views = [
                                SavedView.defaultTable(
                                    visiblePropertyIDs: parentPropertyIDs,
                                    defaultSort: pageCollection.defaultSort
                                )
                            ]
                            try? collection.save(to: collMetaURL)
                        }
                        return collection
                    }

                cols = ContainerIDHealer.heal(
                    cols, seen: &seenCollectionIDs,
                    reID: { $0.id = ULID.generate() },
                    save: {
                        try $0.save(
                            to: $0.folderURL.appendingPathComponent(
                                NexusPaths.pageSetSidecarFilename))
                    }
                )
                let orderedCols = OrderResolver.resolve(
                    cols,
                    persistedOrder: pageCollection.collectionOrder,
                    titleKeyPath: \PageSet.title
                )
                loadedCols[pageCollection.id] = orderedCols

                for collection in orderedCols {
                    try discoverChildSets(
                        of: collection, filter: filter,
                        seenSetIDs: &seenSetIDs, loadedSets: &loadedSets
                    )
                }
            }

            self.depthOneSetsByCollection = loadedCols
            self.childSetsByParentSet = loadedSets
            self.pendingError = nil

            if let updater = indexUpdater {
                for cols in loadedCols.values {
                    for col in cols {
                        do { try updater.upsertPageCollection(col) } catch { self.pendingError = error }
                    }
                }
                for sets in loadedSets.values {
                    for set in sets {
                        try? updater.upsertPageSet(set)
                    }
                }
            }
        } catch {
            self.depthOneSetsByCollection = [:]
            self.childSetsByParentSet = [:]
            self.pendingError = error
        }
    }

    /// Drops a PageCollection's Collections and all their child Sets from the caches.
    /// Called when the parent PageCollection is deleted.
    func removeCollections(forType collectionID: String) {
        for collection in depthOneSetsByCollection[collectionID] ?? [] {
            childSetsByParentSet.removeValue(forKey: collection.id)
        }
        depthOneSetsByCollection.removeValue(forKey: collectionID)
    }

    // MARK: - Collection CRUD

    @discardableResult
    func createPageCollection(name: String, inPageCollection pageCollection: PageCollection) async throws -> PageSet {
        do {
            let existing = depthOneSetsByCollection[pageCollection.id] ?? []
            try CollectionSetValidator.validate(title: name, existingInType: existing)

            let folder = NexusPaths.setFolderURL(
                forTitle: name, inCollectionTitled: pageCollection.title, in: nexus
            )
            let now = Date()
            let coll = PageSet(
                id: ULID.generate(),
                parentID: pageCollection.id,
                title: name,
                folderURL: folder,
                modifiedAt: now
            )
            let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            try Filesystem.createFolderWithMetadata(
                folderURL: folder, metadataURL: metaURL, metadata: coll
            )

            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(coll) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(coll)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: pageCollection.collectionOrder,
                titleKeyPath: \PageSet.title
            )
            depthOneSetsByCollection[pageCollection.id] = arr
            childSetsByParentSet[coll.id] = []
            return coll
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageCollection(_ collection: PageSet, to newName: String) async throws {
        do {
            let pageCollection = pageCollectionProvider?().first(where: { $0.id == collection.parentID })
            let existing = depthOneSetsByCollection[collection.parentID] ?? []
            try CollectionSetValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.setFolderURL(
                forTitle: newName, inCollectionTitled: pageCollection?.title ?? collection.title, in: nexus
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            var updated = collection
            updated.title = newName
            updated.folderURL = newURL
            updated.modifiedAt = Date()
            let metaURL = newURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            do {
                try updated.save(to: metaURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFolder(from: newURL, to: collection.folderURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(updated) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: pageCollection?.collectionOrder,
                    titleKeyPath: \PageSet.title
                )
            }
            depthOneSetsByCollection[collection.parentID] = arr
            // Rebuild child Set URLs since the collection folder moved.
            rebuildFolderURLs(for: updated)
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deletePageCollection(_ collection: PageSet) async throws {
        do {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageSet(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = depthOneSetsByCollection[collection.parentID] ?? []
            arr.removeAll { $0.id == collection.id }
            depthOneSetsByCollection[collection.parentID] = arr
            childSetsByParentSet.removeValue(forKey: collection.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func reorderPageCollections(in pageCollection: PageCollection, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = depthOneSetsByCollection[pageCollection.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        depthOneSetsByCollection[pageCollection.id] = arr
        do {
            try OrderPersister.setPageCollectionOrder(arr.map(\.id), in: pageCollection, nexus: nexus)
        } catch {
            self.pendingError = error
        }
    }


    func updatePageCollectionIcon(_ collection: PageSet, to icon: String?) async throws {
        do {
            var updated = collection
            updated.icon = icon
            updated.modifiedAt = Date()
            let metaURL = collection.folderURL
                .appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            try updated.save(to: metaURL)
            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(updated) } catch { self.pendingError = error }
            }
            var arr = depthOneSetsByCollection[collection.parentID] ?? []
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
            }
            depthOneSetsByCollection[collection.parentID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Collection View CRUD

    func views(in collectionID: String) -> [SavedView] {
        for cols in depthOneSetsByCollection.values {
            if let c = cols.first(where: { $0.id == collectionID }) { return c.views }
        }
        return []
    }

    func mutateCollectionViews<Result>(
        in collectionID: String,
        transform: (inout [SavedView]) throws -> Result
    ) throws -> Result {
        return try withPendingError {
            for (topCollectionID, cols) in depthOneSetsByCollection {
                if let ci = cols.firstIndex(where: { $0.id == collectionID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageSetSidecarFilename)
                    var coll = try PageSet.load(from: meta)
                    let result = try transform(&coll.views)
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    depthOneSetsByCollection[topCollectionID]?[ci] = coll
                    return result
                }
            }
            throw PageCollectionManagerError.typeNotFound
        }
    }

    @discardableResult
    func addView(type: ViewType, to collectionID: String) throws -> SavedView {
        let isGallery = type == .gallery
        let view = SavedView(
            id: "view_\(ULID.generate())",
            name: "Untitled View",
            icon: type.defaultIcon,
            type: type,
            cardSize: isGallery ? .medium : nil,
            showCover: nil)
        return try mutateCollectionViews(in: collectionID) { views in
            views.append(view)
            return view
        }
    }

    @discardableResult
    func duplicateView(_ viewID: String, in collectionID: String) throws -> SavedView {
        try mutateCollectionViews(in: collectionID) { views in
            guard let source = views.first(where: { $0.id == viewID }) else {
                throw PageCollectionManagerError.propertyNotFound
            }
            var copy = source
            copy.id = "view_\(ULID.generate())"
            views.append(copy)
            return copy
        }
    }

    func deleteView(_ viewID: String, in collectionID: String) throws {
        try mutateCollectionViews(in: collectionID) { views in
            guard views.count > 1 else {
                throw PageCollectionManagerError.cannotDeleteLastView
            }
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageCollectionManagerError.propertyNotFound
            }
            views.remove(at: idx)
        }
    }

    func renameView(_ viewID: String, in collectionID: String, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try mutateCollectionViews(in: collectionID) { views in
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageCollectionManagerError.propertyNotFound
            }
            views[idx].name = trimmed
        }
    }

    func updateView(
        _ viewID: String,
        in collectionID: String,
        transform: (inout SavedView) -> Void
    ) throws {
        try mutateCollectionViews(in: collectionID) { views in
            guard let vi = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageCollectionManagerError.propertyNotFound
            }
            transform(&views[vi])
        }
    }

    func setBannerForCollection(_ path: String?, collectionID: String) throws {
        try withPendingError {
            for (topCollectionID, cols) in depthOneSetsByCollection {
                if let ci = cols.firstIndex(where: { $0.id == collectionID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageSetSidecarFilename
                    )
                    var coll = try PageSet.load(from: meta)
                    coll.banner = path
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    depthOneSetsByCollection[topCollectionID]?[ci] = coll
                    return
                }
            }
            throw PageCollectionManagerError.typeNotFound
        }
    }

    // MARK: - Set CRUD

    @discardableResult
    func createPageSet(name: String, in collection: PageSet) async throws -> PageSet {
        do {
            let existing = childSetsByParentSet[collection.id] ?? []
            try PageSetValidator.validate(title: name, existingInCollection: existing)

            let folder = collection.folderURL.appendingPathComponent(name, isDirectory: true)
            let now = Date()
            let set = PageSet(
                id: ULID.generate(),
                parentID: collection.id,
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
            childSetsByParentSet[collection.id] = arr
            return set
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageSet(_ set: PageSet, to newName: String) async throws {
        do {
            let existing = childSetsByParentSet[set.parentID] ?? []
            try PageSetValidator.validate(
                title: newName, existingInCollection: existing, excluding: set
            )

            let newURL = set.folderURL.deletingLastPathComponent()
                .appendingPathComponent(newName, isDirectory: true)
            try Filesystem.renameFolder(from: set.folderURL, to: newURL)

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
                let parentMetaURL = newURL.deletingLastPathComponent()
                    .appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: (try? PageSet.load(from: parentMetaURL))?.setOrder,
                    titleKeyPath: \PageSet.title
                )
            }
            childSetsByParentSet[set.parentID] = arr
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
            var arr = childSetsByParentSet[set.parentID] ?? []
            if let i = arr.firstIndex(where: { $0.id == set.id }) {
                arr[i] = updated
            }
            childSetsByParentSet[set.parentID] = arr
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
            var arr = childSetsByParentSet[set.parentID] ?? []
            arr.removeAll { $0.id == set.id }
            childSetsByParentSet[set.parentID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Moves every descendant `.md` Page of `set` up into the parent
    /// PageCollection folder. Collision-safe: ALL destination names are
    /// checked before anything moves. Each moved Page is re-indexed under
    /// the Collection (page_set_id → nil).
    private func rehomePages(of set: PageSet) throws {
        let collectionFolder = set.folderURL.deletingLastPathComponent()
        let pageFiles = try Self.memberPageFiles(of: set.folderURL)

        var claimed: Set<String> = []
        for url in pageFiles {
            let name = url.lastPathComponent
            guard claimed.insert(name.lowercased()).inserted else {
                throw PageSetValidator.ValidationError.duplicateTitle
            }
            let dest = collectionFolder.appendingPathComponent(name)
            try Filesystem.guardNoFile(at: dest, else: PageSetValidator.ValidationError.duplicateTitle)
        }

        let parentMetaURL = collectionFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let parentCollection = try? PageSet.load(from: parentMetaURL)
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
                    meta, pageCollectionID: parent.parentID, pageSetID: parent.id
                )
            }
        }
    }

    private static func memberPageFiles(of folder: URL) throws -> [URL] {
        try Filesystem.descendantFiles(of: folder) { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
        }
    }

    // MARK: - Move (whole Set between Collections)

    func moveStripTotal(
        for set: PageSet, from sourcePageCollection: PageCollection, to destinationPageCollection: PageCollection
    ) async throws -> Int {
        let strippedIDs = PageContentManager.strippedPropertyIDs(
            from: sourcePageCollection, to: destinationPageCollection)
        guard !strippedIDs.isEmpty else { return 0 }
        let nexusRoot = nexus.rootURL
        return try Self.memberPageFiles(of: set.folderURL).reduce(into: 0) { total, url in
            guard let pf = try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot) else { return }
            total += strippedIDs.intersection(pf.frontmatter.properties.keys).count
        }
    }

    func moveSet(
        _ set: PageSet,
        to destination: PageSet,
        destinationPageCollection: PageCollection,
        sourcePageCollection: PageCollection,
        contentManager: PageContentManager
    ) async throws {
        guard destination.id != set.parentID else { return }
        do {
            try PageSetValidator.validate(
                title: set.title, existingInCollection: pageSets(in: destination))

            let strippedIDs =
                sourcePageCollection.id == destinationPageCollection.id
                ? []
                : PageContentManager.strippedPropertyIDs(from: sourcePageCollection, to: destinationPageCollection)

            let sourceCollectionID = set.parentID
            let newFolder = destination.folderURL.appendingPathComponent(set.title, isDirectory: true)
            try Filesystem.renameFolder(from: set.folderURL, to: newFolder)

            var updated = set
            updated.parentID = destination.id
            updated.folderURL = newFolder
            updated.modifiedAt = Date()
            let metaURL = newFolder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            do {
                try updated.save(to: metaURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFolder(from: newFolder, to: set.folderURL)
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
                throw saveError
            }

            let nexusRoot = nexus.rootURL
            var movedMetas: [PageMeta] = []
            let tx = SchemaTransaction()
            var stagedAny = false
            for url in try Self.memberPageFiles(of: newFolder) {
                guard let pf = try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot)
                else { continue }
                var fm = pf.frontmatter
                let carried = strippedIDs.intersection(fm.properties.keys)
                if !carried.isEmpty {
                    for id in carried { fm.properties.removeValue(forKey: id) }
                    let payload = try AtomicYAMLMarkdown.encode(
                        frontmatter: fm,
                        body: pf.body,
                        preservingFrom: url,
                        modeledKeys: PageFrontmatter.modeledKeys
                    )
                    tx.stage(payload: payload, to: url)
                    stagedAny = true
                }
                movedMetas.append(PageMeta(id: fm.id, title: pf.title, url: url, frontmatter: fm))
            }
            if stagedAny { try tx.commit() }

            if let updater = indexUpdater {
                do { try updater.upsertPageSet(updated) } catch { self.pendingError = error }
                for meta in movedMetas {
                    do {
                        try updater.upsertPage(
                            meta,
                            pageCollectionID: destinationPageCollection.id,
                            pageSetID: updated.id
                        )
                    } catch { self.pendingError = error }
                }
            }

            var sourceArr = childSetsByParentSet[sourceCollectionID] ?? []
            sourceArr.removeAll { $0.id == set.id }
            childSetsByParentSet[sourceCollectionID] = sourceArr

            var destArr = childSetsByParentSet[destination.id] ?? []
            destArr.append(updated)
            destArr = OrderResolver.resolve(
                destArr,
                persistedOrder: destination.setOrder,
                titleKeyPath: \PageSet.title
            )
            childSetsByParentSet[destination.id] = destArr

            // If the Set was previously recorded as a depth-1 Collection in
            // Recents (topTierIDs contains its old parentID), prune that entry —
            // the Set is now depth-2+ and no longer selectable as a collection.
            if topTierIDs.contains(sourceCollectionID) {
                recentsManager?.prune(kind: EntityStateRef.Kind.collection.rawValue, id: set.id)
            }

            await contentManager.loadAll(for: updated)
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    // MARK: - Reorder

    func reorderPageSets(in collection: PageSet, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = childSetsByParentSet[collection.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        childSetsByParentSet[collection.id] = arr
        do {
            try OrderPersister.setPageSetOrder(arr.map(\.id), in: collection)
        } catch {
            self.pendingError = error
        }
    }

    // MARK: - Folder-URL rebuild

    /// Re-derives each cached Set's `folderURL` from the (renamed) parent
    /// Collection's folder. Invoked after a Collection or Page Type rename
    /// moves the folders on disk.
    func rebuildFolderURLs(for collection: PageSet) {
        guard let sets = childSetsByParentSet[collection.id] else { return }
        childSetsByParentSet[collection.id] = sets.map { set in
            var updated = set
            updated.folderURL = collection.folderURL.appendingPathComponent(set.title, isDirectory: true)
            return updated
        }
    }

    /// Rebuilds all Collection folder URLs under a renamed PageCollection, and
    /// propagates the new URLs down to child Sets.
    func rebuildFolderURLsForTypeRename(collectionID: String, newTypeFolder: URL) {
        guard let cols = depthOneSetsByCollection[collectionID] else { return }
        let rebuilt = cols.map { c -> PageSet in
            var updated = c
            updated.folderURL = newTypeFolder.appendingPathComponent(c.title, isDirectory: true)
            return updated
        }
        depthOneSetsByCollection[collectionID] = rebuilt
        for updatedColl in rebuilt {
            rebuildFolderURLs(for: updatedColl)
        }
    }

    // MARK: - Set ancestry

    /// Look up any loaded Set by id across all parent buckets.
    func findSet(byID id: String) -> PageSet? {
        for sets in childSetsByParentSet.values {
            if let s = sets.first(where: { $0.id == id }) { return s }
        }
        return nil
    }

    /// The chain of ancestor Sets from the immediate parent Set of `set` up to
    /// (but not including) the depth-1 Collection. Ordered outermost-first.
    /// Returns [] for a depth-2 Set (whose parent is a Collection, not a Set).
    func setAncestors(from set: PageSet) -> [PageSet] {
        var chain: [PageSet] = []
        var currentID = set.parentID
        while let ancestor = findSet(byID: currentID) {
            chain.insert(ancestor, at: 0)
            currentID = ancestor.parentID
        }
        return chain
    }

    // MARK: - Private helpers

    /// Discovers child folders of `parent` as PageSets, writing them into
    /// `loadedSets` keyed by `parent.id`, then recurses into each discovered set.
    /// Accepts both `_pagecollection.json` (depth-1 alias) and `_pageset.json`.
    /// Missing sidecars are healed in place (same pattern as the Collection-level heal).
    private func discoverChildSets(
        of parent: PageSet,
        filter: FolderFilter,
        seenSetIDs: inout Set<String>,
        loadedSets: inout [String: [PageSet]]
    ) throws {
        var sets = try Filesystem.childFolders(of: parent.folderURL, folderFilter: filter)
            .filter { !$0.lastPathComponent.hasPrefix("_") }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { sub -> PageSet? in
                let setMetaURL = sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                let resolvedMetaURL = Filesystem.fileExists(at: setMetaURL) ? setMetaURL : nil
                let metaURL: URL
                if let url = resolvedMetaURL {
                    metaURL = url
                } else {
                    let healURL = setMetaURL
                    let fresh = PageSet(
                        id: ULID.generate(),
                        parentID: parent.id,
                        title: sub.lastPathComponent,
                        folderURL: sub,
                        modifiedAt: Date()
                    )
                    try? Filesystem.writeMetadataIntoExistingFolder(
                        metadataURL: healURL, metadata: fresh
                    )
                    metaURL = healURL
                }
                guard var set = try? PageSet.load(from: metaURL) else { return nil }
                if set.parentID != parent.id {
                    set.parentID = parent.id
                    try? set.save(to: metaURL)
                }
                return set
            }

        sets = ContainerIDHealer.heal(
            sets, seen: &seenSetIDs,
            reID: { $0.id = ULID.generate() },
            save: {
                try $0.save(
                    to: $0.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
            }
        )
        loadedSets[parent.id] = OrderResolver.resolve(
            sets,
            persistedOrder: parent.setOrder,
            titleKeyPath: \PageSet.title
        )

        for set in sets {
            try discoverChildSets(
                of: set, filter: filter,
                seenSetIDs: &seenSetIDs, loadedSets: &loadedSets
            )
        }
    }

    @discardableResult
    private func withPendingError<T>(
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch {
            pendingError = error
            throw error
        }
    }
}
