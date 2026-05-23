import Foundation

/// CRUD methods for Pages + Items across both Collection-scoped and
/// vault-root-scoped storage. Split out from `ContentManager.swift` for
/// legibility (Part 6.4 of the Commit 4 cleanup). `@MainActor` is inherited
/// from the type declaration; `@Observable` storage is fine across extensions.
///
/// Every CRUD method:
/// - Wraps its body in `do { … } catch { self.pendingError = error; throw error }`
///   so the sidebar toast can surface failures (Part 2).
/// - For rename methods that do two filesystem ops (rename + save), applies
///   the rename-atomicity rollback pattern; if the revert ALSO fails it
///   surfaces a `RenameAtomicityError` (Part 1).
extension ContentManager {

    // MARK: - Page CRUD (Collection-scoped)

    @discardableResult
    func createPage(name: String, in collection: Collection, vault: PageType) async throws -> PageMeta {
        do {
            let existing = pagesByCollection[collection.id] ?? []
            try PageValidator.validate(
                title: name,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(),
                vault: vault,
                existingSiblings: existing,
                context: contextProvider()
            )

            let now = Date()
            let frontmatter = PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now
            )
            let page = PageFile(frontmatter: frontmatter, body: "", title: name)
            let url = NexusPaths.pageFileURL(forTitle: name, in: collection.folderURL)
            try page.save(to: url)

            let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
            var arr = existing
            arr.append(meta)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.pageOrder,
                titleKeyPath: \PageMeta.title
            )
            pagesByCollection[collection.id] = arr
            return meta
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePage(_ page: PageMeta, to newName: String, in collection: Collection, vault: PageType) async throws {
        do {
            let existing = pagesByCollection[collection.id] ?? []
            try PageValidator.validate(
                title: newName,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                existingSiblings: existing,
                context: contextProvider(),
                excluding: page
            )

            let newURL = NexusPaths.pageFileURL(forTitle: newName, in: collection.folderURL)
            // No metadata save here — rename is single-step atomic via
            // FileManager.moveItem. If frontmatter writes are added later,
            // apply the RenameAtomicityError rollback pattern.
            try Filesystem.renameFile(from: page.url, to: newURL)

            var updated = page
            updated.title = newName
            updated.url = newURL

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: collection.pageOrder,
                    titleKeyPath: \PageMeta.title
                )
            }
            pagesByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePage(_ page: PageMeta, in collection: Collection) async throws {
        do {
            try Filesystem.moveToTrash(page.url, in: nexus)
            var arr = pagesByCollection[collection.id] ?? []
            arr.removeAll { $0.id == page.id }
            pagesByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Re-write a Page's body to disk, preserving its frontmatter verbatim.
    /// The editor binds to body only; frontmatter (id, icon, tier1/2/3,
    /// properties, createdAt) round-trips faithfully via PageFile + Yams.
    /// Atomic write happens inside `pageFile.save(to:)` via
    /// `AtomicYAMLMarkdown.write` → `Data.write(.atomic)`.
    ///
    /// In-memory cache (pagesByCollection) is mutated AFTER the disk write
    /// succeeds, so a failed write leaves the cache consistent with disk.
    func updatePage(
        _ page: PageMeta, body: String, in collection: Collection, vault: PageType
    )
        async throws
    {
        do {
            let existing = pagesByCollection[collection.id] ?? []
            try PageValidator.validate(
                title: page.title,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2,
                tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                existingSiblings: existing,
                context: contextProvider(),
                excluding: page
            )

            let pageFile = PageFile(frontmatter: page.frontmatter, body: body, title: page.title)
            try pageFile.save(to: page.url)

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                // Frontmatter unchanged; body lives only on disk (PageMeta is
                // lightweight tracking — body is loaded on demand via PageFile).
                arr[i] = page
            }
            pagesByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Page CRUD (vault-root)

    @discardableResult
    func createPage(name: String, inVaultRoot vault: PageType) async throws -> PageMeta {
        do {
            let existing = pagesByVaultRoot[vault.id] ?? []
            // PageValidator.existingSiblings is a uniqueness check against
            // whatever sibling list the caller passes — passing the vault-root
            // Pages here is correct semantics for a vault-root create.
            try PageValidator.validate(
                title: name,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(),
                vault: vault,
                existingSiblings: existing,
                context: contextProvider()
            )

            let now = Date()
            let frontmatter = PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now
            )
            let page = PageFile(frontmatter: frontmatter, body: "", title: name)
            let url = NexusPaths.pageFileURL(forTitle: name, in: folderURL(for: vault))
            try page.save(to: url)

            let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
            var arr = existing
            arr.append(meta)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: vault.pageOrder,
                titleKeyPath: \PageMeta.title
            )
            pagesByVaultRoot[vault.id] = arr
            return meta
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePage(_ page: PageMeta, to newName: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = pagesByVaultRoot[vault.id] ?? []
            try PageValidator.validate(
                title: newName,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                existingSiblings: existing,
                context: contextProvider(),
                excluding: page
            )

            let newURL = NexusPaths.pageFileURL(forTitle: newName, in: folderURL(for: vault))
            // No metadata save here — single-step atomic via FileManager.moveItem.
            try Filesystem.renameFile(from: page.url, to: newURL)

            var updated = page
            updated.title = newName
            updated.url = newURL

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: vault.pageOrder,
                    titleKeyPath: \PageMeta.title
                )
            }
            pagesByVaultRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePage(_ page: PageMeta, inVaultRoot vault: PageType) async throws {
        do {
            try Filesystem.moveToTrash(page.url, in: nexus)
            var arr = pagesByVaultRoot[vault.id] ?? []
            arr.removeAll { $0.id == page.id }
            pagesByVaultRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Vault-root variant of `updatePage`. Same contract: body-only write,
    /// frontmatter preserved, atomic, in-memory cache mutated after success.
    func updatePage(_ page: PageMeta, body: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = pagesByVaultRoot[vault.id] ?? []
            try PageValidator.validate(
                title: page.title,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2,
                tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                existingSiblings: existing,
                context: contextProvider(),
                excluding: page
            )

            let pageFile = PageFile(frontmatter: page.frontmatter, body: body, title: page.title)
            try pageFile.save(to: page.url)

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                arr[i] = page
            }
            pagesByVaultRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Item CRUD (Collection-scoped)

    @discardableResult
    func createItem(name: String, in collection: Collection, vault: PageType) async throws -> Item {
        do {
            let existing = itemsByCollection[collection.id] ?? []
            try ItemValidator.validate(
                title: name, tier1: [], tier2: [], tier3: [],
                description: "",
                properties: [:],
                vault: vault, existingSiblings: existing,
                context: contextProvider()
            )

            let now = Date()
            let item = Item(
                id: ULID.generate(), title: name, icon: nil, description: "",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.itemFileURL(forTitle: name, in: collection.folderURL)
            try item.save(to: url)

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByCollection[collection.id] = arr
            return item
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItem(_ item: Item, to newName: String, in collection: Collection, vault: PageType) async throws {
        do {
            let existing = itemsByCollection[collection.id] ?? []
            try ItemValidator.validate(
                title: newName,
                tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
                description: item.description, properties: item.properties,
                vault: vault, existingSiblings: existing,
                context: contextProvider(), excluding: item
            )

            let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            let newURL = NexusPaths.itemFileURL(forTitle: newName, in: collection.folderURL)
            var updated = item
            updated.title = newName
            updated.modifiedAt = Date()
            try Filesystem.renameFile(from: oldURL, to: newURL)
            do {
                try updated.save(to: newURL)
            } catch let saveError {
                // Roll back the file rename. If revert ALSO fails, surface the
                // inconsistent state via RenameAtomicityError.
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
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func updateItem(_ item: Item, in collection: Collection, vault: PageType) async throws {
        do {
            let existing = itemsByCollection[collection.id] ?? []
            try ItemValidator.validate(
                title: item.title,
                tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
                description: item.description, properties: item.properties,
                vault: vault, existingSiblings: existing,
                context: contextProvider(), excluding: item
            )

            var updated = item
            updated.modifiedAt = Date()
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
            try updated.save(to: url)

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == item.id }) {
                arr[i] = updated
            }
            itemsByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deleteItem(_ item: Item, in collection: Collection) async throws {
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

    // MARK: - Item CRUD (vault-root)

    @discardableResult
    func createItem(name: String, inVaultRoot vault: PageType) async throws -> Item {
        do {
            let existing = itemsByVaultRoot[vault.id] ?? []
            try ItemValidator.validate(
                title: name, tier1: [], tier2: [], tier3: [],
                description: "",
                properties: [:],
                vault: vault, existingSiblings: existing,
                context: contextProvider()
            )

            let now = Date()
            let item = Item(
                id: ULID.generate(), title: name, icon: nil, description: "",
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now, modifiedAt: now
            )
            let url = NexusPaths.itemFileURL(forTitle: name, in: folderURL(for: vault))
            try item.save(to: url)

            var arr = existing
            arr.append(item)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: vault.itemOrder,
                titleKeyPath: \Item.title
            )
            itemsByVaultRoot[vault.id] = arr
            return item
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renameItem(_ item: Item, to newName: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = itemsByVaultRoot[vault.id] ?? []
            try ItemValidator.validate(
                title: newName,
                tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
                description: item.description, properties: item.properties,
                vault: vault, existingSiblings: existing,
                context: contextProvider(), excluding: item
            )

            let folder = folderURL(for: vault)
            let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
            let newURL = NexusPaths.itemFileURL(forTitle: newName, in: folder)
            var updated = item
            updated.title = newName
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
                    persistedOrder: vault.itemOrder,
                    titleKeyPath: \Item.title
                )
            }
            itemsByVaultRoot[vault.id] = arr
        } catch {
            if !(error is RenameAtomicityError) {
                self.pendingError = error
            }
            throw error
        }
    }

    func deleteItem(_ item: Item, inVaultRoot vault: PageType) async throws {
        do {
            let url = NexusPaths.itemFileURL(forTitle: item.title, in: folderURL(for: vault))
            try Filesystem.moveToTrash(url, in: nexus)
            var arr = itemsByVaultRoot[vault.id] ?? []
            arr.removeAll { $0.id == item.id }
            itemsByVaultRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
