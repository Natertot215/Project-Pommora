import Foundation

/// CRUD methods for Pages across both PageCollection-scoped and
/// Page-Type-root-scoped storage. Split out from `PageContentManager.swift`
/// for legibility. `@MainActor` is inherited from the type declaration;
/// `@Observable` storage is fine across extensions.
///
/// **ParadigmV2 (Task 5.5):** Item CRUD has moved to a parallel
/// `ItemContentManager+CRUD.swift` typed on Item + ItemType + ItemCollection.
///
/// Every CRUD method:
/// - Wraps its body in `do { … } catch { self.pendingError = error; throw error }`
///   so the sidebar toast can surface failures.
/// - For rename methods that do two filesystem ops (rename + save), applies
///   the rename-atomicity rollback pattern; if the revert ALSO fails it
///   surfaces a `RenameAtomicityError`.
extension PageContentManager {

    // MARK: - Page CRUD (PageCollection-scoped)

    @discardableResult
    func createPage(name: String, in collection: PageCollection, vault: PageType) async throws -> PageMeta {
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

    func renamePage(_ page: PageMeta, to newName: String, in collection: PageCollection, vault: PageType) async throws {
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

    func deletePage(_ page: PageMeta, in collection: PageCollection) async throws {
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
        _ page: PageMeta, body: String, in collection: PageCollection, vault: PageType
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

    // MARK: - Page CRUD (Page-Type-root)

    @discardableResult
    func createPage(name: String, inVaultRoot vault: PageType) async throws -> PageMeta {
        do {
            let existing = pagesByTypeRoot[vault.id] ?? []
            // PageValidator.existingSiblings is a uniqueness check against
            // whatever sibling list the caller passes — passing the Type-root
            // Pages here is correct semantics for a Type-root create.
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
            pagesByTypeRoot[vault.id] = arr
            return meta
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePage(_ page: PageMeta, to newName: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = pagesByTypeRoot[vault.id] ?? []
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
            pagesByTypeRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePage(_ page: PageMeta, inVaultRoot vault: PageType) async throws {
        do {
            try Filesystem.moveToTrash(page.url, in: nexus)
            var arr = pagesByTypeRoot[vault.id] ?? []
            arr.removeAll { $0.id == page.id }
            pagesByTypeRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    /// Type-root variant of `updatePage`. Same contract: body-only write,
    /// frontmatter preserved, atomic, in-memory cache mutated after success.
    func updatePage(_ page: PageMeta, body: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = pagesByTypeRoot[vault.id] ?? []
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
            pagesByTypeRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
