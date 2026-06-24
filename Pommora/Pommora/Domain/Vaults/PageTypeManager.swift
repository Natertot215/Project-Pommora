import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPageTypes

@MainActor
@Observable
final class PageTypeManager {
    private(set) var types: [PageType] = []
    /// Depth-1 collections keyed by PageType id. Populated by `loadAll` for backward
    /// compatibility; PageSetManager is the authoritative owner for CRUD. When
    /// `pageSetManager` is wired (production), reads from PageSetManager's live dict
    /// instead so mutations are reflected immediately.
    private var _pageCollectionsByType: [String: [PageCollection]] = [:]
    var pageCollectionsByType: [String: [PageCollection]] {
        if let setManager = pageSetManager {
            var result: [String: [PageCollection]] = [:]
            for typeID in types.map(\.id) {
                result[typeID] = setManager.pageCollectionsByType[typeID] ?? []
            }
            return result
        }
        return _pageCollectionsByType
    }
    var pendingError: (any Error)?

    private let nexus: Nexus

    var nexusID: String { nexus.id }

    var indexUpdater: IndexUpdater?

    /// Injected by NexusEnvironment after both managers are created.
    /// Collection CRUD and discovery delegate to PageSetManager when wired.
    @ObservationIgnored var pageSetManager: PageSetManager?

    /// Fired after a rename moves a PageCollection's folder on disk (its own
    /// rename, or its parent Page Type's) with the updated collection.
    /// Used by tests that wire it manually; in production, URL rebuilds are
    /// handled by PageSetManager directly.
    var onCollectionFolderChanged: (@MainActor (PageCollection) -> Void)?

    @ObservationIgnored fileprivate var _schemaAdapter: PageSchemaAdapter?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func pageCollections(in pageType: PageType) -> [PageCollection] {
        if let setManager = pageSetManager {
            return setManager.pageCollections(in: pageType)
        }
        return _pageCollectionsByType[pageType.id] ?? []
    }

    /// The saved views on a view-bearing container, looked up by id across BOTH
    /// PageTypes and PageCollections. Empty when the id matches no container.
    func views(in containerID: String) -> [SavedView] {
        if let t = types.first(where: { $0.id == containerID }) { return t.views }
        if let setManager = pageSetManager {
            return setManager.views(in: containerID)
        }
        for cols in _pageCollectionsByType.values {
            if let c = cols.first(where: { $0.id == containerID }) { return c.views }
        }
        return []
    }

    func reloadTypeFromDisk(id: String) {
        guard let i = types.firstIndex(where: { $0.id == id }) else { return }
        let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
        if let reloaded = try? PageType.load(from: meta) {
            types[i] = reloaded
        }
    }

    private func withPendingError<T>(
        skipIf: (any Error) -> Bool = { _ in false },
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch {
            if !skipIf(error) { pendingError = error }
            throw error
        }
    }

    // MARK: - Load

    func loadAll(filter: FolderFilter = .empty) async {
        do {
            let root = nexus.rootURL

            let topLevel = try Filesystem.childFolders(of: root, folderFilter: filter)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var typeFolders: [URL] = []
            var loadedTypes: [PageType] = []

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    var pageType = try? PageType.load(from: metaURL)
                else { continue }

                if pageType.views.isEmpty {
                    pageType.views = [
                        SavedView.defaultTable(
                            visiblePropertyIDs: pageType.properties.map(\.id),
                            defaultSort: pageType.defaultSort
                        )
                    ]
                    try? pageType.save(to: metaURL)
                }
                typeFolders.append(folder)
                loadedTypes.append(pageType)
            }

            var seenTypeIDs: Set<String> = []
            loadedTypes = ContainerIDHealer.heal(
                loadedTypes, seen: &seenTypeIDs,
                reID: { $0.id = ULID.generate() },
                save: { try $0.save(to: NexusPaths.vaultMetadataURL(forTitle: $0.title, in: nexus)) }
            )

            // Discover collections for backward compat: tests that call loadAll() and then
            // read pageCollectionsByType before pageSetManager is wired need this populated.
            var loadedCols: [String: [PageCollection]] = [:]
            var seenCollectionIDs: Set<String> = []

            for (folder, pageType) in zip(typeFolders, loadedTypes) {
                let parentPropertyIDs = pageType.properties.map(\.id)
                var cols = try Filesystem.childFolders(of: folder, folderFilter: filter)
                    .filter { !$0.lastPathComponent.hasPrefix("_") }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    .compactMap { sub -> PageCollection? in
                        let collMetaURL = sub.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                        if !Filesystem.fileExists(at: collMetaURL) {
                            let fresh = PageCollection(
                                id: ULID.generate(),
                                typeID: pageType.id,
                                title: sub.lastPathComponent,
                                folderURL: sub,
                                modifiedAt: Date()
                            )
                            try? Filesystem.writeMetadataIntoExistingFolder(
                                metadataURL: collMetaURL, metadata: fresh
                            )
                        }
                        guard var collection = try? PageCollection.load(from: collMetaURL) else {
                            return nil
                        }
                        if collection.typeID != pageType.id {
                            collection.typeID = pageType.id
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
                loadedCols[pageType.id] = OrderResolver.resolve(
                    cols,
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \PageCollection.title
                )
            }

            self.types = OrderResolver.resolve(
                loadedTypes,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
            self._pageCollectionsByType = loadedCols
            self.pendingError = nil

            if let updater = indexUpdater {
                for pageType in self.types {
                    try? updater.upsertPageType(pageType)
                    for collection in loadedCols[pageType.id] ?? [] {
                        try? updater.upsertPageCollection(collection)
                    }
                }
            }
        } catch {
            self.types = []
            self._pageCollectionsByType = [:]
            self.pendingError = error
        }
    }

    // MARK: - PageType CRUD

    @discardableResult
    func createPageType(name: String, icon: String?) async throws -> PageType {
        return try withPendingError {
            try PageTypeValidator.validate(title: name, existing: types)

            let pageType = PageType(
                id: ULID.generate(),
                title: name,
                icon: icon,
                properties: [],
                views: [],
                modifiedAt: Date()
            )
            let folder = NexusPaths.vaultFolderURL(forTitle: name, in: nexus)
            let meta = NexusPaths.vaultMetadataURL(forTitle: name, in: nexus)
            try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: pageType)

            if let updater = indexUpdater {
                do { try updater.upsertPageType(pageType) } catch { self.pendingError = error }
            }

            types.append(pageType)
            _pageCollectionsByType[pageType.id] = []
            types = OrderResolver.resolve(
                types,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
            return pageType
        }
    }

    func renamePageType(_ pageType: PageType, to newName: String) async throws {
        try withPendingError(skipIf: { $0 is RenameAtomicityError }) {
            try PageTypeValidator.validate(title: newName, existing: types, excluding: pageType)

            let oldFolder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
            let newFolder = NexusPaths.vaultFolderURL(forTitle: newName, in: nexus)
            try Filesystem.renameFolder(from: oldFolder, to: newFolder)

            var updated = pageType
            updated.title = newName
            updated.modifiedAt = Date()
            let newMeta = NexusPaths.vaultMetadataURL(forTitle: newName, in: nexus)
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
                do { try updater.upsertPageType(updated) } catch { self.pendingError = error }
            }

            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i] = updated
                if let setManager = pageSetManager {
                    setManager.rebuildFolderURLsForTypeRename(typeID: pageType.id, newTypeFolder: newFolder)
                } else if let oldCols = _pageCollectionsByType[pageType.id] {
                    let rebuilt = oldCols.map { c -> PageCollection in
                        var u = c
                        u.folderURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                        return u
                    }
                    _pageCollectionsByType[pageType.id] = rebuilt
                    rebuilt.forEach { onCollectionFolderChanged?($0) }
                }
                types = OrderResolver.resolve(
                    types,
                    persistedOrder: readPersistedPageTypeOrder(),
                    titleKeyPath: \PageType.title
                )
            }
        }
    }

    func updatePageTypeIcon(_ pageType: PageType, to icon: String?) async throws {
        try withPendingError {
            var updated = pageType
            updated.icon = icon
            updated.modifiedAt = Date()
            let meta = NexusPaths.vaultMetadataURL(forTitle: pageType.title, in: nexus)
            try updated.save(to: meta)
            if let updater = indexUpdater {
                do { try updater.upsertPageType(updated) } catch { self.pendingError = error }
            }
            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i] = updated
            }
        }
    }

    func deletePageType(_ pageType: PageType) async throws {
        try withPendingError {
            let folder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageType(id: pageType.id) } catch { self.pendingError = error }
            }
            types.removeAll { $0.id == pageType.id }
            _pageCollectionsByType.removeValue(forKey: pageType.id)
        }
    }

    // MARK: - PageCollection CRUD

    @discardableResult
    func createPageCollection(name: String, inPageType pageType: PageType) async throws -> PageCollection {
        if let setManager = pageSetManager {
            return try await setManager.createPageCollection(name: name, inPageType: pageType)
        }
        return try withPendingError {
            let existing = _pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(title: name, existingInType: existing)

            let folder = NexusPaths.collectionFolderURL(
                forTitle: name, inVaultTitled: pageType.title, in: nexus
            )
            let now = Date()
            let coll = PageCollection(
                id: ULID.generate(),
                typeID: pageType.id,
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
                titleKeyPath: \PageCollection.title
            )
            _pageCollectionsByType[pageType.id] = arr
            return coll
        }
    }

    func renamePageCollection(_ collection: PageCollection, to newName: String) async throws {
        if let setManager = pageSetManager {
            return try await setManager.renamePageCollection(collection, to: newName)
        }
        try withPendingError(skipIf: { $0 is RenameAtomicityError }) {
            guard let pageType = types.first(where: { $0.id == collection.typeID }) else { return }
            let existing = _pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: pageType.title, in: nexus
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
                    persistedOrder: pageType.collectionOrder,
                    titleKeyPath: \PageCollection.title
                )
            }
            _pageCollectionsByType[pageType.id] = arr
            onCollectionFolderChanged?(updated)
        }
    }

    func deletePageCollection(_ collection: PageCollection) async throws {
        if let setManager = pageSetManager {
            return try await setManager.deletePageCollection(collection)
        }
        try withPendingError {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageCollection(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = _pageCollectionsByType[collection.typeID] ?? []
            arr.removeAll { $0.id == collection.id }
            _pageCollectionsByType[collection.typeID] = arr
        }
    }

    func reorderPageTypes(fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = types
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != types else { return }
        types = arr
        do {
            try OrderPersister.setVaultOrder(arr.map(\.id), in: nexus)
        } catch {
            self.pendingError = error
        }
    }

    func reorderPageCollections(in pageType: PageType, fromOffsets source: IndexSet, toOffset destination: Int) {
        if let setManager = pageSetManager {
            setManager.reorderPageCollections(in: pageType, fromOffsets: source, toOffset: destination)
            return
        }
        var arr = _pageCollectionsByType[pageType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        _pageCollectionsByType[pageType.id] = arr
        do {
            try OrderPersister.setPageCollectionOrder(arr.map(\.id), in: pageType, nexus: nexus)
            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i].collectionOrder = arr.map(\.id)
            }
        } catch {
            self.pendingError = error
        }
    }

    func updatePageCollectionIcon(_ collection: PageCollection, to icon: String?) async throws {
        if let setManager = pageSetManager {
            return try await setManager.updatePageCollectionIcon(collection, to: icon)
        }
        try withPendingError {
            var updated = collection
            updated.icon = icon
            updated.modifiedAt = Date()
            let metaURL = collection.folderURL
                .appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            try updated.save(to: metaURL)
            if let updater = indexUpdater {
                do { try updater.upsertPageCollection(updated) } catch { self.pendingError = error }
            }
            var arr = _pageCollectionsByType[collection.typeID] ?? []
            if let i = arr.firstIndex(where: { $0.id == collection.id }) {
                arr[i] = updated
            }
            _pageCollectionsByType[collection.typeID] = arr
        }
    }

    // MARK: - Open-in

    func setOpenIn(_ mode: OpenInMode, forVault typeID: String) async throws {
        guard let i = types.firstIndex(where: { $0.id == typeID }) else {
            throw PageTypeManagerError.typeNotFound
        }
        var updated = types[i]
        updated.openIn = mode
        updated.modifiedAt = Date()
        try withPendingError {
            try updated.save(to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus))
        }
        types[i] = updated
    }

    // MARK: - Banner

    func setBanner(_ path: String?, forContainer containerID: String) async throws {
        try withPendingError {
            if let i = types.firstIndex(where: { $0.id == containerID }) {
                let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
                var updated = try PageType.load(from: meta)
                updated.banner = path
                updated.modifiedAt = Date()
                try updated.save(to: meta)
                types[i] = updated
                return
            }
            if let setManager = pageSetManager {
                try setManager.setBannerForCollection(path, collectionID: containerID)
                return
            }
            for (typeID, cols) in _pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == containerID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename
                    )
                    var coll = try PageCollection.load(from: meta)
                    coll.banner = path
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    _pageCollectionsByType[typeID]?[ci] = coll
                    return
                }
            }
            throw PageTypeManagerError.typeNotFound
        }
    }

    private func readPersistedPageTypeOrder() -> [String]? {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? AtomicJSON.decode(NexusState.self, from: url))?.vaultOrder
    }

}

// MARK: - Schema CRUD errors

enum PageTypeManagerError: Error, Equatable {
    case typeNotFound
    case propertyNotFound
    case lossyChangeRequiresConfirmation
    case indexOutOfBounds
    case cannotDeleteLastView
}

extension PageTypeManagerError: LocalizedError {
    var errorDescription: String? { PropertyEditorErrorMessage.string(for: self) }
}

// MARK: - Schema CRUD methods

extension PageTypeManager {

    func addProperty(_ definition: PropertyDefinition, to typeID: String) async throws {
        try withPendingError {
            try PerTypeSchemaService.addProperty(definition, in: typeID, on: schemaAdapter)
        }
    }

    func renameProperty(id propertyID: String, in typeID: String, to newName: String) async throws {
        try withPendingError {
            try PerTypeSchemaService.renameProperty(id: propertyID, in: typeID, to: newName, on: schemaAdapter)
        }
    }

    func updateView(
        _ viewID: String,
        in containerID: String,
        transform: (inout SavedView) -> Void
    ) async throws {
        try await mutateViews(in: containerID) { views in
            guard let vi = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            transform(&views[vi])
        }
    }

    private func mutateViews<Result>(
        in containerID: String,
        transform: (inout [SavedView]) throws -> Result
    ) async throws -> Result {
        return try withPendingError {
            if let i = types.firstIndex(where: { $0.id == containerID }) {
                let meta = NexusPaths.vaultMetadataURL(forTitle: types[i].title, in: nexus)
                var updated = try PageType.load(from: meta)
                let result = try transform(&updated.views)
                updated.modifiedAt = Date()
                try updated.save(to: meta)
                types[i] = updated
                return result
            }
            if let setManager = pageSetManager {
                return try setManager.mutateCollectionViews(in: containerID, transform: transform)
            }
            for (typeID, cols) in _pageCollectionsByType {
                if let ci = cols.firstIndex(where: { $0.id == containerID }) {
                    let meta = cols[ci].folderURL.appendingPathComponent(
                        NexusPaths.pageCollectionSidecarFilename)
                    var coll = try PageCollection.load(from: meta)
                    let result = try transform(&coll.views)
                    coll.modifiedAt = Date()
                    try coll.save(to: meta)
                    _pageCollectionsByType[typeID]?[ci] = coll
                    return result
                }
            }
            throw PageTypeManagerError.typeNotFound
        }
    }

    @discardableResult
    func addView(type: ViewType, to containerID: String) async throws -> SavedView {
        let isGallery = type == .gallery
        let view = SavedView(
            id: "view_\(ULID.generate())",
            name: "Untitled View",
            icon: type.defaultIcon,
            type: type,
            cardSize: isGallery ? .medium : nil,
            showCover: nil)
        return try await mutateViews(in: containerID) { views in
            views.append(view)
            return view
        }
    }

    @discardableResult
    func duplicateView(_ viewID: String, in containerID: String) async throws -> SavedView {
        try await mutateViews(in: containerID) { views in
            guard let source = views.first(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            var copy = source
            copy.id = "view_\(ULID.generate())"
            views.append(copy)
            return copy
        }
    }

    func deleteView(_ viewID: String, in containerID: String) async throws {
        try await mutateViews(in: containerID) { views in
            guard views.count > 1 else {
                throw PageTypeManagerError.cannotDeleteLastView
            }
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            views.remove(at: idx)
        }
    }

    func renameView(_ viewID: String, in containerID: String, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await mutateViews(in: containerID) { views in
            guard let idx = views.firstIndex(where: { $0.id == viewID }) else {
                throw PageTypeManagerError.propertyNotFound
            }
            views[idx].name = trimmed
        }
    }

    func duplicateProperty(id propertyID: String, in typeID: String) async throws {
        try withPendingError {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw PageTypeManagerError.propertyNotFound
            }

            var duplicated = types[i].properties[j]
            duplicated.id = ReservedPropertyID.mintUserPropertyID()
            duplicated.name = "\(duplicated.name) (copy)"

            try PropertyDefinitionValidator.validate(
                duplicated, in: types[i].properties, nexus: NexusContext.forTypeResolution(in: nexus))

            var updatedType = types[i]
            updatedType.properties.append(duplicated)
            updatedType.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updatedType.title, in: nexus)
            try updatedType.save(to: meta)

            if let updater = indexUpdater {
                let position = updatedType.properties.count - 1
                do {
                    try updater.upsertPropertyDefinition(
                        duplicated, owningTypeID: typeID, owningTypeKind: "page_type", position: position
                    )
                } catch { self.pendingError = error }
            }

            types[i] = updatedType
        }
    }

    func updateProperty(
        id propertyID: String,
        in typeID: String,
        transform: (inout PropertyDefinition) -> Void
    ) async throws {
        try withPendingError {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let j = types[i].properties.firstIndex(where: { $0.id == propertyID }) else {
                throw PageTypeManagerError.propertyNotFound
            }

            var updatedDef = types[i].properties[j]
            transform(&updatedDef)

            var siblings = types[i].properties
            siblings.remove(at: j)
            try PropertyDefinitionValidator.validate(
                updatedDef, in: siblings, nexus: NexusContext.forTypeResolution(in: nexus))

            var updatedType = types[i]
            updatedType.properties[j] = updatedDef
            updatedType.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updatedType.title, in: nexus)
            try updatedType.save(to: meta)

            if let updater = indexUpdater {
                do {
                    try updater.upsertPropertyDefinition(
                        updatedDef, owningTypeID: typeID, owningTypeKind: "page_type", position: j
                    )
                } catch { self.pendingError = error }
            }

            types[i] = updatedType
        }
    }

    func deleteProperty(id propertyID: String, in typeID: String) async throws {
        try withPendingError {
            try PerTypeSchemaService.deleteProperty(id: propertyID, in: typeID, on: schemaAdapter)
        }
        try await mutateViews(in: typeID) { views in
            for i in views.indices {
                SavedViewMutations.scrubDeletedProperty(&views[i], propertyID: propertyID)
            }
        }
    }

    func reorderProperty(id propertyID: String, in typeID: String, toIndex newIndex: Int) async throws {
        try withPendingError {
            try PerTypeSchemaService.reorderProperty(id: propertyID, in: typeID, toIndex: newIndex, on: schemaAdapter)
        }
    }

    func changeType(
        of propertyID: String,
        in typeID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false
    ) async throws {
        try withPendingError {
            try PerTypeSchemaService.changeType(
                of: propertyID,
                in: typeID,
                to: newType,
                dropConflictingValues: dropConflictingValues,
                on: schemaAdapter)
        }
    }
}

// MARK: - Per-type schema adapter

extension PageTypeManager {

    fileprivate var schemaAdapter: PageSchemaAdapter {
        if let existing = _schemaAdapter { return existing }
        let adapter = PageSchemaAdapter(self)
        _schemaAdapter = adapter
        return adapter
    }

    fileprivate final class PageSchemaAdapter: PerTypeSchemaAdapter {
        unowned let m: PageTypeManager
        private var stagedType: PageType?

        init(_ m: PageTypeManager) { self.m = m }

        func properties(forTypeID typeID: String) throws -> [PropertyDefinition] {
            guard let pt = m.types.first(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            return pt.properties
        }

        func commitType(properties: [PropertyDefinition], forTypeID typeID: String) throws {
            guard let i = m.types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            var updated = m.types[i]
            updated.properties = properties
            updated.modifiedAt = Date()
            try updated.save(to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: m.nexus))
            m.types[i] = updated
        }

        func stageType(
            properties: [PropertyDefinition], forTypeID typeID: String, into tx: SchemaTransaction
        ) throws {
            guard let i = m.types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            var updated = m.types[i]
            updated.properties = properties
            updated.modifiedAt = Date()
            try tx.stage(updated, to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: m.nexus))
            stagedType = updated
        }

        func commitStagedType(forTypeID typeID: String) {
            guard let updated = stagedType,
                let i = m.types.firstIndex(where: { $0.id == typeID })
            else { return }
            m.types[i] = updated
            stagedType = nil
        }

        func memberFiles(forTypeID typeID: String) throws -> [URL] {
            guard let pt = m.types.first(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: pt.title, in: m.nexus)
            return try Filesystem.descendantFiles(of: typeFolder) { url in
                url.pathExtension == "md"
            }
        }

        func stripPropertyFromMembers(
            _ propertyID: String, forTypeID typeID: String, into tx: SchemaTransaction
        ) throws {
            let pageFiles = try memberFiles(forTypeID: typeID)
            MemberFileStrip.forEach(pageFiles) { pageURL in
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { return }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(
                    frontmatter: fm, body: body,
                    preservingFrom: pageURL, modeledKeys: PageFrontmatter.modeledKeys)
                tx.stage(payload: data, to: pageURL)
            }
        }

        var indexOwningTypeKind: String { "page_type" }
        var indexUpdater: IndexUpdater? { m.indexUpdater }
        var validationContext: NexusContext { NexusContext.forTypeResolution(in: m.nexus) }
        var errTypeNotFound: any Error { PageTypeManagerError.typeNotFound }
        var errPropertyNotFound: any Error { PageTypeManagerError.propertyNotFound }
        var errLossyChangeRequiresConfirmation: any Error {
            PageTypeManagerError.lossyChangeRequiresConfirmation
        }
        var errIndexOutOfBounds: any Error { PageTypeManagerError.indexOutOfBounds }
        func recordIndexError(_ error: any Error) { m.pendingError = error }
    }
}
