import Foundation
import Observation

/// Manages Pages (`.md`) + Items (`.json`) inside a Vault. The spec allows
/// Content to live either directly in a Vault's root folder or inside a
/// Collection sub-folder — both are first-class. Collection-scoped state and
/// vault-root-scoped state are kept in parallel dictionaries to avoid nullable
/// `Collection` plumbing through every CRUD signature.
///
/// PageMeta = lightweight tracking value (no body in memory); full PageFile is
/// loaded on demand by the editor (post-v0.2). Items load entirely since they're
/// small row-shaped records.
///
/// All CRUD methods take the parent `Vault` because Page/Item validation needs
/// the Vault's property schema. Validation runs before every write.
@MainActor
@Observable
final class ContentManager {
    /// Collection-scoped Pages keyed by Collection.id.
    private(set) var pagesByCollection: [String: [PageMeta]] = [:]
    /// Collection-scoped Items keyed by Collection.id.
    private(set) var itemsByCollection: [String: [Item]] = [:]
    /// Vault-root Pages (directly inside the Vault folder, NOT in a Collection)
    /// keyed by Vault.id.
    private(set) var pagesByVaultRoot: [String: [PageMeta]] = [:]
    /// Vault-root Items keyed by Vault.id. Surfaces only in detail-pane Tables
    /// in v0.2 — sidebar doesn't render Items — but the data layer supports it.
    private(set) var itemsByVaultRoot: [String: [Item]] = [:]
    var pendingError: (any Error)?

    private let nexus: Nexus
    private let contextProvider: @MainActor () -> NexusContext

    init(nexus: Nexus, contextProvider: @escaping @MainActor () -> NexusContext) {
        self.nexus = nexus
        self.contextProvider = contextProvider
    }

    // MARK: - Accessors

    func pages(in collection: Collection) -> [PageMeta] {
        pagesByCollection[collection.id] ?? []
    }

    func items(in collection: Collection) -> [Item] {
        itemsByCollection[collection.id] ?? []
    }

    func pages(in vault: Vault) -> [PageMeta] {
        pagesByVaultRoot[vault.id] ?? []
    }

    func items(in vault: Vault) -> [Item] {
        itemsByVaultRoot[vault.id] ?? []
    }

    // MARK: - Path helpers (vault-root)

    /// Vault.folderURL isn't a stored property — it's always derived from the
    /// nexus root + the vault's title. Centralized here so every vault-root
    /// CRUD path uses the same derivation.
    private func folderURL(for vault: Vault) -> URL {
        NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
    }

    // MARK: - Load (Collection-scoped)

    func loadAll(for collection: Collection) async {
        do {
            let pageFiles = try Filesystem.children(of: collection.folderURL) { url in
                url.pathExtension == "md"
            }
            let pageMetas: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.load(from: url) else { return nil }
                return PageMeta(id: pf.frontmatter.id, title: pf.title, url: url, frontmatter: pf.frontmatter)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            let itemFiles = try Filesystem.children(of: collection.folderURL) { url in
                url.pathExtension == "json"
            }
            let items: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            pagesByCollection[collection.id] = pageMetas
            itemsByCollection[collection.id] = items
            pendingError = nil
        } catch {
            pagesByCollection[collection.id] = []
            itemsByCollection[collection.id] = []
            pendingError = error
        }
    }

    // MARK: - Load (vault-root)

    /// Scans the vault's root folder for `.md` Pages and `.json` Items DIRECTLY
    /// (non-recursive — does not descend into Collection sub-folders, since
    /// those are loaded separately via `loadAll(for: collection)`).
    /// Skips the `_vault.json` sidecar (any `_`-prefixed file) and `_collection.json`
    /// sidecars (also `_`-prefixed but only ever found in sub-folders).
    func loadAll(for vault: Vault) async {
        let folder = folderURL(for: vault)
        do {
            let pageFiles = try Filesystem.children(of: folder) { url in
                url.pathExtension == "md"
                    && !url.lastPathComponent.hasPrefix("_")
            }
            let pageMetas: [PageMeta] = pageFiles.compactMap { url in
                guard let pf = try? PageFile.load(from: url) else { return nil }
                return PageMeta(id: pf.frontmatter.id, title: pf.title, url: url, frontmatter: pf.frontmatter)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            let itemFiles = try Filesystem.children(of: folder) { url in
                url.pathExtension == "json"
                    && !url.lastPathComponent.hasPrefix("_")
            }
            let items: [Item] = itemFiles.compactMap { try? Item.load(from: $0) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            pagesByVaultRoot[vault.id] = pageMetas
            itemsByVaultRoot[vault.id] = items
            pendingError = nil
        } catch {
            pagesByVaultRoot[vault.id] = []
            itemsByVaultRoot[vault.id] = []
            pendingError = error
        }
    }

    // MARK: - Page CRUD (Collection-scoped)

    func createPage(name: String, in collection: Collection, vault: Vault) async throws {
        let existing = pagesByCollection[collection.id] ?? []
        try PageValidator.validate(
            title: name,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(),
            vault: vault,
            existingInCollection: existing,
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
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        pagesByCollection[collection.id] = arr
    }

    func renamePage(_ page: PageMeta, to newName: String, in collection: Collection, vault: Vault) async throws {
        let existing = pagesByCollection[collection.id] ?? []
        try PageValidator.validate(
            title: newName,
            tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
            properties: page.frontmatter.properties,
            createdAt: page.frontmatter.createdAt,
            vault: vault,
            existingInCollection: existing,
            context: contextProvider(),
            excluding: page
        )

        let newURL = NexusPaths.pageFileURL(forTitle: newName, in: collection.folderURL)
        try Filesystem.renameFile(from: page.url, to: newURL)

        var updated = page
        updated.title = newName
        updated.url = newURL

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == page.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        pagesByCollection[collection.id] = arr
    }

    func deletePage(_ page: PageMeta, in collection: Collection) async throws {
        try Filesystem.deleteFile(at: page.url)
        var arr = pagesByCollection[collection.id] ?? []
        arr.removeAll { $0.id == page.id }
        pagesByCollection[collection.id] = arr
    }

    // MARK: - Page CRUD (vault-root)

    @discardableResult
    func createPage(name: String, inVaultRoot vault: Vault) async throws -> PageMeta {
        let existing = pagesByVaultRoot[vault.id] ?? []
        // PageValidator.existingInCollection is a uniqueness check against
        // whatever sibling list the caller passes — passing the vault-root
        // Pages here is correct semantics; the field name is just slightly
        // misleading.
        try PageValidator.validate(
            title: name,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(),
            vault: vault,
            existingInCollection: existing,
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
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        pagesByVaultRoot[vault.id] = arr
        return meta
    }

    func renamePage(_ page: PageMeta, to newName: String, inVaultRoot vault: Vault) async throws {
        let existing = pagesByVaultRoot[vault.id] ?? []
        try PageValidator.validate(
            title: newName,
            tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
            properties: page.frontmatter.properties,
            createdAt: page.frontmatter.createdAt,
            vault: vault,
            existingInCollection: existing,
            context: contextProvider(),
            excluding: page
        )

        let newURL = NexusPaths.pageFileURL(forTitle: newName, in: folderURL(for: vault))
        try Filesystem.renameFile(from: page.url, to: newURL)

        var updated = page
        updated.title = newName
        updated.url = newURL

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == page.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        pagesByVaultRoot[vault.id] = arr
    }

    func deletePage(_ page: PageMeta, inVaultRoot vault: Vault) async throws {
        try Filesystem.deleteFile(at: page.url)
        var arr = pagesByVaultRoot[vault.id] ?? []
        arr.removeAll { $0.id == page.id }
        pagesByVaultRoot[vault.id] = arr
    }

    // MARK: - Item CRUD (Collection-scoped)

    func createItem(name: String, in collection: Collection, vault: Vault) async throws {
        let existing = itemsByCollection[collection.id] ?? []
        try ItemValidator.validate(
            title: name, tier1: [], tier2: [], tier3: [],
            description: "",
            properties: [:],
            vault: vault, existingInCollection: existing,
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
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        itemsByCollection[collection.id] = arr
    }

    func renameItem(_ item: Item, to newName: String, in collection: Collection, vault: Vault) async throws {
        let existing = itemsByCollection[collection.id] ?? []
        try ItemValidator.validate(
            title: newName,
            tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
            description: item.description, properties: item.properties,
            vault: vault, existingInCollection: existing,
            context: contextProvider(), excluding: item
        )

        let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
        let newURL = NexusPaths.itemFileURL(forTitle: newName, in: collection.folderURL)
        var updated = item
        updated.title = newName
        updated.modifiedAt = Date()
        try Filesystem.renameFile(from: oldURL, to: newURL)
        try updated.save(to: newURL)

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == item.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        itemsByCollection[collection.id] = arr
    }

    func updateItem(_ item: Item, in collection: Collection, vault: Vault) async throws {
        let existing = itemsByCollection[collection.id] ?? []
        try ItemValidator.validate(
            title: item.title,
            tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
            description: item.description, properties: item.properties,
            vault: vault, existingInCollection: existing,
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
    }

    func deleteItem(_ item: Item, in collection: Collection) async throws {
        let url = NexusPaths.itemFileURL(forTitle: item.title, in: collection.folderURL)
        try Filesystem.deleteFile(at: url)
        var arr = itemsByCollection[collection.id] ?? []
        arr.removeAll { $0.id == item.id }
        itemsByCollection[collection.id] = arr
    }

    // MARK: - Item CRUD (vault-root)

    @discardableResult
    func createItem(name: String, inVaultRoot vault: Vault) async throws -> Item {
        let existing = itemsByVaultRoot[vault.id] ?? []
        try ItemValidator.validate(
            title: name, tier1: [], tier2: [], tier3: [],
            description: "",
            properties: [:],
            vault: vault, existingInCollection: existing,
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
        arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        itemsByVaultRoot[vault.id] = arr
        return item
    }

    func renameItem(_ item: Item, to newName: String, inVaultRoot vault: Vault) async throws {
        let existing = itemsByVaultRoot[vault.id] ?? []
        try ItemValidator.validate(
            title: newName,
            tier1: item.tier1, tier2: item.tier2, tier3: item.tier3,
            description: item.description, properties: item.properties,
            vault: vault, existingInCollection: existing,
            context: contextProvider(), excluding: item
        )

        let folder = folderURL(for: vault)
        let oldURL = NexusPaths.itemFileURL(forTitle: item.title, in: folder)
        let newURL = NexusPaths.itemFileURL(forTitle: newName, in: folder)
        var updated = item
        updated.title = newName
        updated.modifiedAt = Date()
        try Filesystem.renameFile(from: oldURL, to: newURL)
        try updated.save(to: newURL)

        var arr = existing
        if let i = arr.firstIndex(where: { $0.id == item.id }) {
            arr[i] = updated
            arr.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        itemsByVaultRoot[vault.id] = arr
    }

    func deleteItem(_ item: Item, inVaultRoot vault: Vault) async throws {
        let url = NexusPaths.itemFileURL(forTitle: item.title, in: folderURL(for: vault))
        try Filesystem.deleteFile(at: url)
        var arr = itemsByVaultRoot[vault.id] ?? []
        arr.removeAll { $0.id == item.id }
        itemsByVaultRoot[vault.id] = arr
    }
}
