import Foundation

/// CRUD methods for Items across both ItemCollection-scoped and
/// Item-Type-root-scoped storage. Split out from `ItemContentManager.swift`
/// for legibility, mirroring `PageContentManager+CRUD.swift`.
///
/// **ParadigmV2 (Task 5.5 — stub-and-progressively-replace):**
/// - Property validation against the Item Type's schema lands in Phase 6
///   once `ItemValidator` is rewired off `PageType`. Until then, CRUD uses an
///   inline title-uniqueness check matching `PageContentManager`'s shape.
/// - Item-Type-root paths assume the `<nexus>/Items/<TypeFolder>/` wrapper
///   exists; NexusAdopter materializes the wrapper in Phase 6.
///
/// Every CRUD method:
/// - Wraps its body in `do { … } catch { self.pendingError = error; throw error }`
///   so the sidebar toast can surface failures.
/// - For rename methods that do two filesystem ops (rename + save), applies
///   the rename-atomicity rollback pattern; if the revert ALSO fails it
///   surfaces a `RenameAtomicityError`.
extension ItemContentManager {

    // MARK: - Title uniqueness (transitional)
    //
    // Used until Phase 6 wires a proper ItemValidator-vs-ItemType. Matches the
    // case-insensitive uniqueness rule that ItemValidator enforces today.
    fileprivate func enforceTitleUniqueness(
        _ trimmed: String,
        among siblings: [Item],
        excluding: Item? = nil
    ) throws {
        let invalidChars: Set<Character> = ["/", "\\", ":"]
        guard !trimmed.isEmpty else { throw ItemCRUDError.emptyTitle }
        guard trimmed.allSatisfy({ !invalidChars.contains($0) }) else {
            throw ItemCRUDError.invalidTitleCharacters
        }
        let conflict = siblings.contains { i in
            i.id != excluding?.id && i.title.lowercased() == trimmed.lowercased()
        }
        if conflict { throw ItemCRUDError.duplicateTitle }
    }

    // MARK: - Item CRUD (ItemCollection-scoped)

    @discardableResult
    func createItem(name: String, in collection: ItemCollection, type itemType: ItemType) async throws -> Item {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let existing = itemsByCollection[collection.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing)

            let now = Date()
            let item = Item(
                id: ULID.generate(), title: trimmed, icon: nil, description: "",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            try item.save(to: url)

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByCollection[collection.id] = arr
            _ = itemType  // schema validation arrives Phase 6
            return item
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItem(
        _ item: Item, to newName: String, in collection: ItemCollection, type itemType: ItemType
    ) async throws {
        do {
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            let existing = itemsByCollection[collection.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            let newURL = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            var updated = item
            updated.title = trimmed
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: collection.itemOrder,
                    titleKeyPath: \Item.title
                )
            }
            itemsByCollection[collection.id] = arr
            _ = itemType  // schema validation arrives Phase 6
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateItem(_ item: Item, in collection: ItemCollection, type itemType: ItemType) async throws {
        do {
            let trimmed = item.title.trimmingCharacters(in: .whitespaces)
            let existing = itemsByCollection[collection.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            var updated = item
            updated.modifiedAt = Date()
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: collection.folderURL)
            try updated.save(to: url)

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
            }
            itemsByCollection[collection.id] = arr
            _ = itemType  // schema validation arrives Phase 6
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteItem(_ item: Item, in collection: ItemCollection) async throws {
        do {
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            try Filesystem.moveToTrash(url, in: nexus)
            var arr = itemsByCollection[collection.id] ?? []
            arr.removeAll { $0.id == item.id }
            itemsByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Item CRUD (Item-Type-root)

    @discardableResult
    func createItem(name: String, inTypeRoot itemType: ItemType) async throws -> Item {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let existing = itemsByTypeRoot[itemType.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing)

            let now = Date()
            let item = Item(
                id: ULID.generate(), title: trimmed, icon: nil, description: "",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: folderURL(for: itemType))
            try item.save(to: url)

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: itemType.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByTypeRoot[itemType.id] = arr
            return item
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItem(_ item: Item, to newName: String, inTypeRoot itemType: ItemType) async throws {
        do {
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            let existing = itemsByTypeRoot[itemType.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            let folder = folderURL(for: itemType)
            let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
            let newURL = NexusPaths.itemFileURL(forTitle: trimmed, in: folder)
            var updated = item
            updated.title = trimmed
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                do {
                    try Filesystem.renameFile(from: newURL, to: oldURL)
                    throw saveError
                } catch let revertError {
                    let combined = RenameAtomicityError(saveError: saveError, revertError: revertError)
                    self.pendingError = combined
                    throw combined
                }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: itemType.itemOrder,
                    titleKeyPath: \Item.title
                )
            }
            itemsByTypeRoot[itemType.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateItem(_ item: Item, inTypeRoot itemType: ItemType) async throws {
        do {
            let trimmed = item.title.trimmingCharacters(in: .whitespaces)
            let existing = itemsByTypeRoot[itemType.id] ?? []
            try enforceTitleUniqueness(trimmed, among: existing, excluding: item)

            var updated = item
            updated.modifiedAt = Date()
            let url = NexusPaths.itemFileURL(forTitle: trimmed, in: folderURL(for: itemType))
            try updated.save(to: url)

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
            }
            itemsByTypeRoot[itemType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteItem(_ item: Item, inTypeRoot itemType: ItemType) async throws {
        do {
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: folderURL(for: itemType))
            try Filesystem.moveToTrash(url, in: nexus)
            var arr = itemsByTypeRoot[itemType.id] ?? []
            arr.removeAll { $0.id == item.id }
            itemsByTypeRoot[itemType.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }
}

/// Errors surfaced by `ItemContentManager` CRUD methods during the
/// Task 5.5 transitional window. Phase 6 replaces these with the
/// upgraded `ItemValidator` typed on `ItemType`.
enum ItemCRUDError: Error, LocalizedError, Equatable {
    case emptyTitle
    case invalidTitleCharacters
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Name can't be empty."
        case .invalidTitleCharacters: return "Name can't contain / \\ :"
        case .duplicateTitle: return "An Item with that name already exists."
        }
    }
}
