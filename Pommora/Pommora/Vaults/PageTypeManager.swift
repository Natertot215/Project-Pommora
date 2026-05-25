import Foundation
import Observation
import SwiftUI  // for Array.move(fromOffsets:toOffset:) used by reorderPageTypes/Collections

@MainActor
@Observable
final class PageTypeManager {
    private(set) var types: [PageType] = []
    private(set) var pageCollectionsByType: [String: [PageCollection]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus

    /// Current Nexus ID — used by the drag system's cross-window guard.
    var nexusID: String { nexus.id }

    /// Injected by NexusManager in Phase E.7. Nil until wired; CRUD methods
    /// call it post-commit as a best-effort non-fatal write (filesystem is canonical).
    var indexUpdater: IndexUpdater?

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func pageCollections(in pageType: PageType) -> [PageCollection] {
        pageCollectionsByType[pageType.id] ?? []
    }

    // MARK: - Load

    func loadAll() async {
        do {
            // flatlayout: PageType folders sit at the Nexus root. Discovery
            // filters folders by presence of `_pagetype.json`; folders carrying
            // any of the other per-kind sidecars (Items/Agenda/Collection) or
            // no recognized sidecar are skipped. NexusAdopter is the single
            // canonical migration surface — it surfaces unrecognized / legacy
            // folders to the user via the preview sheet on launch. No in-loader
            // auto-heal here (would race the adopter and produce inconsistent
            // state).
            let root = nexus.rootURL

            let topLevel = try Filesystem.childFolders(of: root)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { !$0.lastPathComponent.hasPrefix("_") }

            var loadedTypes: [PageType] = []
            var loadedCols: [String: [PageCollection]] = [:]

            for folder in topLevel {
                let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
                guard Filesystem.fileExists(at: metaURL),
                    let pageType = try? PageType.load(from: metaURL)
                else { continue }
                loadedTypes.append(pageType)

                // Discover PageCollections (sub-folders with `_pagecollection.json`; skip _- and .-prefixed).
                // A sub-folder inside an already-flat PageType can only be a PageCollection,
                // so if the sidecar is missing (folder created by hand in Finder, or pre-existing
                // before adoption), write a fresh one in place. Best-effort: a write failure
                // falls through to the existing nil-skip behavior.
                let cols = try Filesystem.childFolders(of: folder)
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
                        return try? PageCollection.load(from: collMetaURL)
                    }
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
            self.pageCollectionsByType = loadedCols
            self.pendingError = nil
        } catch {
            self.types = []
            self.pageCollectionsByType = [:]
            self.pendingError = error
        }
    }

    // MARK: - PageType CRUD

    func createPageType(name: String, icon: String?) async throws {
        do {
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
            pageCollectionsByType[pageType.id] = []
            types = OrderResolver.resolve(
                types,
                persistedOrder: readPersistedPageTypeOrder(),
                titleKeyPath: \PageType.title
            )
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageType(_ pageType: PageType, to newName: String) async throws {
        do {
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
                // Roll back folder rename. Per spec: do NOT touch
                // collectionsByType here — in-memory rebuild only runs on the
                // save-success branch below.
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
                // Rebuild PageCollection in-memory under new parent path (id + type_id unchanged;
                // schema sidecar moved with its folder, just re-derive folderURL).
                // Preserve pageOrder so a Page Type rename doesn't drop persisted ordering.
                if let oldCols = pageCollectionsByType[pageType.id] {
                    let rebuilt = oldCols.map { c -> PageCollection in
                        let newCollURL = newFolder.appendingPathComponent(c.title, isDirectory: true)
                        return PageCollection(
                            id: c.id,
                            typeID: c.typeID,
                            title: c.title,
                            folderURL: newCollURL,
                            modifiedAt: c.modifiedAt,
                            pageOrder: c.pageOrder
                        )
                    }
                    pageCollectionsByType[pageType.id] = rebuilt
                }
                types = OrderResolver.resolve(
                    types,
                    persistedOrder: readPersistedPageTypeOrder(),
                    titleKeyPath: \PageType.title
                )
            }
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updatePageTypeIcon(_ pageType: PageType, to icon: String?) async throws {
        do {
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
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePageType(_ pageType: PageType) async throws {
        do {
            let folder = NexusPaths.vaultFolderURL(forTitle: pageType.title, in: nexus)
            try Filesystem.moveToTrash(folder, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageType(id: pageType.id) } catch { self.pendingError = error }
            }
            types.removeAll { $0.id == pageType.id }
            pageCollectionsByType.removeValue(forKey: pageType.id)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - PageCollection CRUD

    func createPageCollection(name: String, inPageType pageType: PageType) async throws {
        do {
            let existing = pageCollectionsByType[pageType.id] ?? []
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
            pageCollectionsByType[pageType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePageCollection(_ collection: PageCollection, to newName: String) async throws {
        do {
            guard let pageType = types.first(where: { $0.id == collection.typeID }) else { return }
            let existing = pageCollectionsByType[pageType.id] ?? []
            try PageCollectionValidator.validate(
                title: newName, existingInType: existing, excluding: collection
            )

            let newURL = NexusPaths.collectionFolderURL(
                forTitle: newName, inVaultTitled: pageType.title, in: nexus
            )
            try Filesystem.renameFolder(from: collection.folderURL, to: newURL)

            // Bump modified_at in the sidecar at its new location. Preserve
            // pageOrder so a rename doesn't drop persisted ordering.
            let now = Date()
            let updated = PageCollection(
                id: collection.id,
                typeID: collection.typeID,
                title: newName,
                folderURL: newURL,
                modifiedAt: now,
                pageOrder: collection.pageOrder
            )
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
            pageCollectionsByType[pageType.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deletePageCollection(_ collection: PageCollection) async throws {
        do {
            try Filesystem.moveToTrash(collection.folderURL, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePageCollection(id: collection.id) } catch { self.pendingError = error }
            }
            var arr = pageCollectionsByType[collection.typeID] ?? []
            arr.removeAll { $0.id == collection.id }
            pageCollectionsByType[collection.typeID] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Reorders Page Types in response to a sidebar drag (v0.2.8.0). Matches the
    /// SwiftUI `.onMove(perform:)` signature. New full ID order persists to
    /// `.nexus/state.json`.
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

    /// Reorders PageCollections within `pageType`. New ID order persists to the parent
    /// Page Type's schema sidecar.
    func reorderPageCollections(in pageType: PageType, fromOffsets source: IndexSet, toOffset destination: Int) {
        var arr = pageCollectionsByType[pageType.id] ?? []
        let before = arr
        arr.move(fromOffsets: source, toOffset: destination)
        guard arr != before else { return }
        pageCollectionsByType[pageType.id] = arr
        do {
            try OrderPersister.setPageCollectionOrder(arr.map(\.id), in: pageType, nexus: nexus)
            // Keep the in-memory PageType's collectionOrder in sync.
            if let i = types.firstIndex(where: { $0.id == pageType.id }) {
                types[i].collectionOrder = arr.map(\.id)
            }
        } catch {
            self.pendingError = error
        }
    }

    /// Reads the persisted Page Type sibling order from `.nexus/state.json`. Returns
    /// nil if no state.json exists or no `vault_order` has been recorded — the
    /// resolver falls back to alphabetic in that case.
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
}

// MARK: - Schema CRUD methods

extension PageTypeManager {

    // MARK: - Add property

    /// Adds a property definition to a Page Type's schema. If `definition.id` is empty,
    /// a new user-property ID (`prop_<ulid>`) is minted. Validates against existing
    /// properties via `PropertyDefinitionValidator`. Schema-only write (member files
    /// are not touched — identity is stored by ID).
    func addProperty(_ definition: PropertyDefinition, to typeID: String) async throws {
        do {
            guard let i = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }

            var def = definition
            if def.id.isEmpty {
                def.id = ReservedPropertyID.mintUserPropertyID()
            }

            try PropertyDefinitionValidator.validate(def, in: types[i].properties)

            var updated = types[i]
            updated.properties.append(def)
            updated.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                let position = updated.properties.count - 1
                do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: position) } catch { self.pendingError = error }
            }

            types[i] = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Rename property

    /// Renames a property by its stable ID. Schema-only write — member files keyed by
    /// `id` are not touched (rename-safe by design per the domain model).
    func renameProperty(id propertyID: String, in typeID: String, to newName: String) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            var renamedDef = types[typeIndex].properties[propIndex]
            renamedDef.name = newName

            // Build the schema with the renamed definition substituted in, so validation
            // can check name-uniqueness against the rest of the schema (excluding itself).
            var otherProps = types[typeIndex].properties
            otherProps.remove(at: propIndex)
            // Validate name only — borrow the validator but supply a def with a fresh
            // temp-unique ID so the duplicate-ID rule doesn't fire. We only care about
            // the name-uniqueness check here.
            var validationDef = renamedDef
            validationDef.id = ReservedPropertyID.mintUserPropertyID()
            try PropertyDefinitionValidator.validate(validationDef, in: otherProps)

            var updated = types[typeIndex]
            updated.properties[propIndex] = renamedDef
            updated.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                do { try updater.upsertPropertyDefinition(renamedDef, owningTypeID: typeID, owningTypeKind: "page_type", position: propIndex) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Delete property

    /// Deletes a property from the schema. Atomically removes the schema entry and
    /// strips the corresponding key from every member Page's frontmatter
    /// `properties` dictionary via `SchemaTransaction`.
    func deleteProperty(id propertyID: String, in typeID: String) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            var updated = types[typeIndex]
            updated.properties.remove(at: propIndex)
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try tx.stage(updated, to: meta)

            // Stage member-file rewrites: strip the property key from every Page's frontmatter.
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: updated.title, in: nexus)
            let pageFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { url in
                    url.pathExtension == "md"
                })
            for pageURL in pageFiles {
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { continue }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                tx.stage(payload: data, to: pageURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                do { try updater.deletePropertyDefinition(id: propertyID) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Reorder property

    /// Moves a property to a new index within the schema's `properties` array.
    /// Schema-only write — member files are not touched.
    func reorderProperty(id propertyID: String, in typeID: String, toIndex newIndex: Int) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            var props = types[typeIndex].properties
            let clampedIndex = min(max(newIndex, 0), props.count - 1)
            guard clampedIndex != propIndex else { return }

            guard clampedIndex >= 0 && clampedIndex < props.count else {
                throw PageTypeManagerError.indexOutOfBounds
            }

            props.move(
                fromOffsets: IndexSet(integer: propIndex),
                toOffset: clampedIndex > propIndex ? clampedIndex + 1 : clampedIndex)

            var updated = types[typeIndex]
            updated.properties = props
            updated.modifiedAt = Date()

            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try updated.save(to: meta)

            if let updater = indexUpdater {
                for (pos, def) in updated.properties.enumerated() {
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: pos) } catch { self.pendingError = error }
                }
            }

            types[typeIndex] = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Change property type

    /// Changes the type of an existing property.
    ///
    /// **Lossless path** (`oldType == newType`): updates the schema sidecar only.
    ///
    /// **Lossy path** (`oldType != newType`):
    /// - `dropConflictingValues == false` → throws `.lossyChangeRequiresConfirmation`
    ///   so the caller can surface a confirmation dialog.
    /// - `dropConflictingValues == true` → atomically updates the schema sidecar and
    ///   strips the property's value from every member Page's frontmatter via
    ///   `SchemaTransaction`.
    func changeType(
        of propertyID: String,
        in typeID: String,
        to newType: PropertyType,
        dropConflictingValues: Bool = false
    ) async throws {
        do {
            guard let typeIndex = types.firstIndex(where: { $0.id == typeID }) else {
                throw PageTypeManagerError.typeNotFound
            }
            guard let propIndex = types[typeIndex].properties.firstIndex(where: { $0.id == propertyID })
            else {
                throw PageTypeManagerError.propertyNotFound
            }

            let oldType = types[typeIndex].properties[propIndex].type

            if oldType == newType {
                // Lossless: schema-only write to bump modifiedAt.
                var updated = types[typeIndex]
                updated.properties[propIndex].type = newType
                updated.modifiedAt = Date()
                let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
                try updated.save(to: meta)
                if let updater = indexUpdater {
                    let def = updated.properties[propIndex]
                    do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: propIndex) } catch { self.pendingError = error }
                }
                types[typeIndex] = updated
                return
            }

            // Lossy cross-type change.
            guard dropConflictingValues else {
                throw PageTypeManagerError.lossyChangeRequiresConfirmation
            }

            var updated = types[typeIndex]
            updated.properties[propIndex].type = newType
            updated.modifiedAt = Date()

            let tx = SchemaTransaction()

            // Stage updated schema sidecar.
            let meta = NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus)
            try tx.stage(updated, to: meta)

            // Stage member-file rewrites: strip the conflicting property value from
            // every Page's frontmatter so no stale cross-type value lingers.
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: updated.title, in: nexus)
            let pageFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { url in
                    url.pathExtension == "md"
                })
            for pageURL in pageFiles {
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { continue }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                tx.stage(payload: data, to: pageURL)
            }

            try tx.commit()

            if let updater = indexUpdater {
                let def = updated.properties[propIndex]
                do { try updater.upsertPropertyDefinition(def, owningTypeID: typeID, owningTypeKind: "page_type", position: propIndex) } catch { self.pendingError = error }
            }

            types[typeIndex] = updated
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
