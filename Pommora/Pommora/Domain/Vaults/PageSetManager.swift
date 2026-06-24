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
    /// Depth-1: Collections keyed by their parent PageType id.
    private(set) var pageCollectionsByType: [String: [PageSet]] = [:]
    /// Depth-2: Sets keyed by their parent PageCollection id.
    private(set) var pageSetsByCollection: [String: [PageSet]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Injected by NexusEnvironment alongside the other managers. Nil until
    /// wired; CRUD methods call it post-commit as a best-effort non-fatal
    /// write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    /// Closure supplying the current PageType array. Wired by NexusEnvironment
    /// so Collection reorders and renames can read the parent type's `collectionOrder`.
    @ObservationIgnored var pageTypeProvider: (() -> [PageType])?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func pageCollections(in pageType: PageType) -> [PageSet] {
        pageCollectionsByType[pageType.id] ?? []
    }

    func pageSets(in collection: PageSet) -> [PageSet] {
        pageSetsByCollection[collection.id] ?? []
    }

    // MARK: - Load

    /// Discovers depth-1 PageCollections as direct children of each PageType folder,
    /// and depth-2 PageSets as direct children of each Collection folder.
    /// Missing sidecars are healed in place; drifted parent IDs are re-pointed.
    func loadAll(types: [PageType], filter: FolderFilter = .empty) async {
        do {
            var loadedCols: [String: [PageSet]] = [:]
            var loadedSets: [String: [PageSet]] = [:]
            var seenCollectionIDs: Set<String> = []
            var seenSetIDs: Set<String> = []

            for pageType in types {
                let typeFolder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
                do { let __m = "PMDBG typeFolder=\(typeFolder.path) exists=\(FileManager.default.fileExists(atPath: typeFolder.path)) children=\((try? Filesystem.childFolders(of: typeFolder, folderFilter: filter))?.map(\.lastPathComponent) ?? [])\n"; let __p = (NSTemporaryDirectory() as NSString).appendingPathComponent("pmdbg_loadall.txt"); if !FileManager.default.fileExists(atPath: __p) { FileManager.default.createFile(atPath: __p, contents: nil) }; if let __h = FileHandle(forWritingAtPath: __p) { __h.seekToEndOfFile(); __h.write(__m.data(using: .utf8)!); try? __h.close() } } // DEBUG_INSTRUMENT
                let parentPropertyIDs = pageType.properties.map(\.id)

                var cols = try Filesystem.childFolders(of: typeFolder, folderFilter: filter)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> PageSet? in
                        let collMetaURL = sub.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                        if !Filesystem.fileExists(at: collMetaURL) {
                            let fresh = PageSet(
                                id: ULID.generate(),
                                parentID: pageType.id,
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
                        if collection.parentID != pageType.id {
                            collection.parentID = pageType.id
                            try? collection.save(to: collMetaURL)
                        }
                        if collection.views.isEmpty {
                            collection.views = [
                                SavedView.defaultTable(
                                    visiblePropertyIDs: parentPropertyIDs,
                                    defaultSort: pageType.defaultSort
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
                                NexusPaths.pageCollectionSidecarFilename))
                    }
                )
                let orderedCols = OrderResolver.resolve(
                    cols,
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \PageSet.title
                )
                loadedCols[pageType.id] = orderedCols

                // Depth-2: discover Sets under each Collection
                for collection in orderedCols {
                    var sets = try Filesystem.childFolders(of: collection.folderURL, folderFilter: filter)
                        .filter { !$0.lastPathComponent.hasPrefix("_") }
                        .filter { !$0.lastPathComponent.hasPrefix(".") }
                        .compactMap { sub -> PageSet? in
                            let metaURL = sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                            if !Filesystem.fileExists(at: metaURL) {
                                let fresh = PageSet(
                                    id: ULID.generate(),
                                    parentID: collection.id,
                                    title: sub.lastPathComponent,
                                    folderURL: sub,
                                    modifiedAt: Date()
                                )
                                try? Filesystem.writeMetadataIntoExistingFolder(
                                    metadataURL: metaURL, metadata: fresh
                                )
                            }
                            guard var set = try? PageSet.load(from: metaURL) else { return nil }
                            if set.parentID != collection.id {
                                set.parentID = collection.id
                                try? set.save(to: metaURL)
                            }
                            return set
                        }

                    sets = ContainerIDHealer.heal(
                        sets, seen: &seenSetIDs,
                        reID: { $0.id = ULID.generate() },
                        save: {
                            try $0.save(
                                to: $0.folderURL.appendingPathComponent(
                                    NexusPaths.pageSetSidecarFilename))
                        }
                    )
                    loadedSets[collection.id] = OrderResolver.resolve(
                        sets,
                        persistedOrder: collection.setOrder,
                        titleKeyPath: \PageSet.title
                    )
                }
            }

            self.pageCollectionsByType = loadedCols
            do { let __m = "PMDBG loadAll types=\(types.map(\.title)) loadedCols=\(loadedCols.mapValues { $0.map(\.title) })\n"; let __p = (NSTemporaryDirectory() as NSString).appendingPathComponent("pmdbg_loadall.txt"); if !FileManager.default.fileExists(atPath: __p) { FileManager.default.createFile(atPath: __p, contents: nil) }; if let __h = FileHandle(forWritingAtPath: __p) { __h.seekToEndOfFile(); __h.write(__m.data(using: .utf8)!); try? __h.close() } } // DEBUG_INSTRUMENT
            self.pageSetsByCollection = loadedSets
            self.pendingError = nil

            if let updater = indexUpdater {
                for cols in loadedCols.values {
                    for col in cols {
                        do { try updater.upsertPageCollection(col) } catch { let __m = "PMDBG upsertCollection FAILED \(col.title): \(error)\n"; let __p = (NSTemporaryDirectory() as NSString).appendingPathComponent("pmdbg_loadall.txt"); if !FileManager.default.fileExists(atPath: __p) { FileManager.default.createFile(atPath: __p, contents: nil) }; if let __h = FileHandle(forWritingAtPath: __p) { __h.seekToEndOfFile(); __h.write(__m.data(using: .utf8)!); try? __h.close() } } // DEBUG_INSTRUMENT
                    }
                }
                for sets in loadedSets.values {
                    for set in sets {
                        try? updater.upsertPageSet(set)
                    }
                }
            }
        } catch {
            self.pageCollectionsByType = [:]
            self.pageSetsByCollection = [:]
            self.pendingError = error
        }
    }

    /// Drops a PageType's Collections and all their child Sets from the caches.
    /// Called when the parent PageType is deleted.
    func removeCollections(forType typeID: String) {
        for collection in pageCollectionsByType[typeID] ?? [] {
            pageSetsByCollection.removeValue(forKey: collection.id)
        }
        pageCollectionsByType.removeValue(forKey: typeID)
    }

    // MARK: - Collection CRUD

    @discardableResult
    func createPageCollection(name: String, inPageType pageType: PageType) async throws -> PageSet {
        do {
            let existing = pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(title: name, existingInType: existing)

            let folder = NexusPaths.collectionFolderURL(
                forTitle: name, inVaultTitled: pageType.title, in: nexus
            )
            let now = Date()
            let coll = PageSet(
                id: ULID.generate(),
                parentID: pageType.id,
                title: name,
                folderURL: folder,
                modifiedAt: now
            )
            let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
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
                persistedOrder: pageType.collectionOrder,
                titleKeyPath: \PageSet.title
            )
            pageCollectionsByType[pageType.id] = arr
            pageSetsByCollection[coll.id] = []
            return coll
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageCollection(_ collection: PageSet, to newName: String) async throws {
        do {
            let pageType = pageTypeProvider?().first(where: { $0.id == collection.parentID })
            let existing = pageCollectionsByType[collection.parentID] ?? []
            try PageCollectionValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: pageType?.title ?? collection.title, in: nexus
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            var updated = collection
            updated.title = newName
            updated.folderURL = newURL
            updated.modifiedAt = Date()
            let metaURL = newURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
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
                    persistedOrder: pageType?.collectionOrder,
                    titleKeyPath: \PageSet.title
                )
            }
            pageCollectionsByType[collection.parentID] = arr
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
                do { try updater.deletePageCollection(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = pageCollectionsByType[collection.parentID] ?? []
            arr.removeAll { $0.id == collection.id }
            pageCollectionsByType[collection.parentID] = arr
            pageSetsByCollection.removeValue(forKey: collection.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func reorderPageCollections(in pageType: PageType, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = pageCollectionsByType[pageType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pageCollectionsByType[pageType.id] = arr
        do {
            try OrderPersister.setPageCollectionOrder(arr.map(\.id), in: pageType, nexus: nexus)
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
                .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            try updated.save(to: metaURL)
            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(updated) } catch { self.pendingError = error }
            }
            var arr = pageCollectionsByType[collection.parentID] ?? []
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
            }
            pageCollectionsByType[collection.parentID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Collection View CRUD

    func views(in collectionID: String) -> [SavedView] {
        for cols in pageCollectionsByType.values {
            if let c = cols.first(where: { $0.id == collectionID }) { return c.views }
        }
        return []
    }

    func mutateCollectionViews<Result>(
        in collectionID: String,
        transform: (inout [SavedView]) throws -> Result
    ) throws -> Result {
        return try withPendingError {
            for (typeID, cols) in pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == collectionID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename)
                    var coll = try PageSet.load(from: meta)
                    let result = try transform(&coll.views)
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    pageCollectionsByType[typeID]?[ci] = coll
                    return result
                }
            }
            throw PageTypeManagerError.typeNotFound
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
                throw PageTypeManagerError.propertyNotFound
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
                throw PageTypeManagerError.cannotDeleteLastView
            }
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            views.remove(at: idx)
        }
    }

    func renameView(_ viewID: String, in collectionID: String, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try mutateCollectionViews(in: collectionID) { views in
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
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
                throw PageTypeManagerError.propertyNotFound
            }
            transform(&views[vi])
        }
    }

    func setBannerForCollection(_ path: String?, collectionID: String) throws {
        try withPendingError {
            for (typeID, cols) in pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == collectionID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename
                    )
                    var coll = try PageSet.load(from: meta)
                    coll.banner = path
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    pageCollectionsByType[typeID]?[ci] = coll
                    return
                }
            }
            throw PageTypeManagerError.typeNotFound
        }
    }

    // MARK: - Set CRUD

    @discardableResult
    func createPageSet(name: String, in collection: PageSet) async throws -> PageSet {
        do {
            let existing = pageSetsByCollection[collection.id] ?? []
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
            pageSetsByCollection[collection.id] = arr
            return set
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageSet(_ set: PageSet, to newName: String) async throws {
        do {
            let existing = pageSetsByCollection[set.parentID] ?? []
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
                    .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: (try? PageSet.load(from: parentMetaURL))?.setOrder,
                    titleKeyPath: \PageSet.title
                )
            }
            pageSetsByCollection[set.parentID] = arr
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
            var arr = pageSetsByCollection[set.parentID] ?? []
            if let i = arr.firstIndex(where: { $0.id == set.id }) {
                arr[i] = updated
            }
            pageSetsByCollection[set.parentID] = arr
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
            var arr = pageSetsByCollection[set.parentID] ?? []
            arr.removeAll { $0.id == set.id }
            pageSetsByCollection[set.parentID] = arr
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

        let parentMetaURL = collectionFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
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
                    meta, pageTypeID: parent.parentID, pageCollectionID: parent.id, pageSetID: nil
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
        for set: PageSet, from sourceVault: PageType, to destinationVault: PageType
    ) async throws -> Int {
        let strippedIDs = PageContentManager.strippedPropertyIDs(
            from: sourceVault, to: destinationVault)
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
        destinationVault: PageType,
        sourceVault: PageType,
        contentManager: PageContentManager
    ) async throws {
        guard destination.id != set.parentID else { return }
        do {
            try PageSetValidator.validate(
                title: set.title, existingInCollection: pageSets(in: destination))

            let strippedIDs =
                sourceVault.id == destinationVault.id
                ? []
                : PageContentManager.strippedPropertyIDs(from: sourceVault, to: destinationVault)

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
                            pageTypeID: destinationVault.id,
                            pageCollectionID: destination.id,
                            pageSetID: updated.id
                        )
                    } catch { self.pendingError = error }
                }
            }

            var sourceArr = pageSetsByCollection[sourceCollectionID] ?? []
            sourceArr.removeAll { $0.id == set.id }
            pageSetsByCollection[sourceCollectionID] = sourceArr

            var destArr = pageSetsByCollection[destination.id] ?? []
            destArr.append(updated)
            destArr = OrderResolver.resolve(
                destArr,
                persistedOrder: destination.setOrder,
                titleKeyPath: \PageSet.title
            )
            pageSetsByCollection[destination.id] = destArr

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
    /// Collection's folder. Invoked after a Collection or Page Type rename
    /// moves the folders on disk.
    func rebuildFolderURLs(for collection: PageSet) {
        guard let sets = pageSetsByCollection[collection.id] else { return }
        pageSetsByCollection[collection.id] = sets.map { set in
            var updated = set
            updated.folderURL = collection.folderURL.appendingPathComponent(set.title, isDirectory: true)
            return updated
        }
    }

    /// Rebuilds all Collection folder URLs under a renamed PageType, and
    /// propagates the new URLs down to child Sets.
    func rebuildFolderURLsForTypeRename(typeID: String, newTypeFolder: URL) {
        guard let cols = pageCollectionsByType[typeID] else { return }
        let rebuilt = cols.map { c -> PageSet in
            var updated = c
            updated.folderURL = newTypeFolder.appendingPathComponent(c.title, isDirectory: true)
            return updated
        }
        pageCollectionsByType[typeID] = rebuilt
        for updatedColl in rebuilt {
            rebuildFolderURLs(for: updatedColl)
        }
    }

    // MARK: - Private helpers

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
