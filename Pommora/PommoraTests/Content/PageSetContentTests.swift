import Foundation
import GRDB
import Testing

@testable import Pommora

/// PageSet-scoped content behavior on PageContentManager (Sets Task 5):
/// load scoping (Set subtrees roll up into the Set, NOT the Collection),
/// Set-scoped Page CRUD carrying `page_set_id`, strip-free in-vault moves
/// across every location combination, the cross-Type strip regression, and
/// Set-scoped reorder persistence.
///
/// Fixtures mirror `MovePageTests` (hand-built Vault/Collection folders) +
/// `NexusWideUniquenessTests` (index-seeded parents for FK-bearing CRUD).
@MainActor
@Suite("PageSetContentTests")
struct PageSetContentTests {

    // MARK: - Load scoping

    @Test("loadAll(for: set) rolls nested folders into the Set; collection load excludes Set subtrees")
    func loadScopesSetPagesOutOfCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageType(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        let set = try makePageSet(title: "Drafts", in: coll)

        _ = try writePage(titled: "RootPage", in: coll.folderURL)
        _ = try writePage(titled: "SetPage", in: set.folderURL)
        // A folder INSIDE the Set isn't a recognized container — its page
        // rolls up into the Set, not the Collection.
        let nested = set.folderURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try writePage(titled: "DeepPage", in: nested)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll(for: set)
        await manager.loadAll(for: coll)

        #expect(Set(manager.pages(in: set).map(\.title)) == ["SetPage", "DeepPage"])
        #expect(manager.pages(in: coll).map(\.title) == ["RootPage"])
    }

    // MARK: - Set-scoped CRUD

    @Test("Set-scoped create/rename/update/delete round-trip with page_set_id index rows")
    func setScopedCRUDRoundTrips() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = updater

        // Create.
        let meta = try await manager.createPage(name: "Alpha", in: set, collection: coll, vault: vault)
        let createdURL = NexusPaths.pageFileURL(forTitle: "Alpha", in: set.folderURL)
        #expect(FileManager.default.fileExists(atPath: createdURL.path))
        #expect(manager.pages(in: set).map(\.id) == [meta.id])

        let pageID = meta.id  // hoist before the dbQueue closure (@Sendable)
        let collID = coll.id
        let setID = set.id
        let createdRow = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(createdRow?["page_collection_id"] as String? == collID)
        #expect(createdRow?["page_set_id"] as String? == setID)

        // Rename.
        try await manager.renamePage(meta, to: "Beta", in: set, collection: coll, vault: vault)
        let renamedURL = NexusPaths.pageFileURL(forTitle: "Beta", in: set.folderURL)
        #expect(!FileManager.default.fileExists(atPath: createdURL.path))
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
        let renamedRow = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(renamedRow?["title"] as String? == "Beta")
        #expect(renamedRow?["page_set_id"] as String? == setID)

        // Update body.
        let renamed = manager.pages(in: set).first!
        try await manager.updatePage(renamed, body: "set body", in: set, collection: coll, vault: vault)
        #expect(try PageFile.load(from: renamedURL).body == "set body")

        // Delete.
        try await manager.deletePage(renamed, in: set)
        #expect(!FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(manager.pages(in: set).isEmpty)
        let remaining = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE id = ?", arguments: [pageID]) ?? -1
        }
        #expect(remaining == 0)
    }

    @Test("Set-scoped create rejects a duplicate title among Set siblings")
    func setScopedCreateDupRejected() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageType(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        let set = try makePageSet(title: "Drafts", in: coll)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        _ = try await manager.createPage(name: "Alpha", in: set, collection: coll, vault: vault)
        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "Alpha", in: set, collection: coll, vault: vault)
        }
    }

    // MARK: - In-vault moves (strip-free)

    @Test("In-vault moves across set/collection/vault-root preserve frontmatter verbatim")
    func inVaultMovesPreserveFrontmatter() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let prop = PropertyDefinition(id: "prop_keep", name: "Priority", type: .select)
        let vault = try makePageType(nexus: nexus, title: "Notes", properties: [prop])
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        let setA = try makePageSet(title: "SetA", in: coll)
        let setB = try makePageSet(title: "SetB", in: coll)

        // Hand-author the page so a FOREIGN frontmatter key rides along —
        // strip-free moves must carry it by value (mirrors MovePageTests).
        let pageID = ULID.generate()
        let srcURL = NexusPaths.pageFileURL(forTitle: "Doc", in: coll.folderURL)
        let raw = """
            ---
            id: \(pageID)
            plugin_color: "#abcdef"
            tier1: []
            tier2: []
            tier3: []
            properties:
              prop_keep: high
            created_at: 2026-01-01T00:00:00Z
            ---

            the moved body
            """
        try raw.data(using: .utf8)!.write(to: srcURL, options: [.atomic])
        let original = try PageFile.load(from: srcURL)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let page = PageMeta(id: pageID, title: "Doc", url: srcURL, frontmatter: original.frontmatter)
        manager.pagesByCollection[coll.id] = [page]

        func assertPreserved(at url: URL) throws {
            let moved = try PageFile.load(from: url)
            #expect(moved.frontmatter == original.frontmatter)
            #expect(moved.body == original.body)
        }
        func currentMeta(_ pages: [PageMeta]) throws -> PageMeta {
            try #require(pages.first(where: { $0.id == pageID }))
        }

        // 1. Collection root → SetA.
        try await manager.movePageToSet(
            page, from: .collection(coll, vault: vault), to: setA, collection: coll, vault: vault)
        let inSetA = try currentMeta(manager.pages(in: setA))
        #expect(manager.pages(in: coll).isEmpty)
        try assertPreserved(at: inSetA.url)

        // 2. SetA → SetB.
        try await manager.movePageToSet(
            inSetA, from: .set(setA, collection: coll, vault: vault), to: setB, collection: coll, vault: vault)
        let inSetB = try currentMeta(manager.pages(in: setB))
        #expect(manager.pages(in: setA).isEmpty)
        try assertPreserved(at: inSetB.url)

        // 3. SetB → Collection root.
        try await manager.movePageOutOfSet(
            inSetB, from: setB, collection: coll, vault: vault, to: .collection(coll, vault: vault))
        let backInColl = try currentMeta(manager.pages(in: coll))
        #expect(manager.pages(in: setB).isEmpty)
        try assertPreserved(at: backInColl.url)

        // 4. Collection root → SetA → vault root.
        try await manager.movePageToSet(
            backInColl, from: .collection(coll, vault: vault), to: setA, collection: coll, vault: vault)
        let inSetAAgain = try currentMeta(manager.pages(in: setA))
        try await manager.movePageOutOfSet(
            inSetAAgain, from: setA, collection: coll, vault: vault, to: .vaultRoot(vault))
        let atRoot = try currentMeta(manager.pages(in: vault))
        #expect(manager.pages(in: setA).isEmpty)
        try assertPreserved(at: atRoot.url)

        // The foreign key survived every hop by value.
        let finalText = try String(contentsOf: atRoot.url, encoding: .utf8)
        #expect(finalText.contains("plugin_color"))
    }

    @Test("In-vault moves re-point page_set_id / page_collection_id index rows")
    func movesRePointIndexRows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = try makePageType(nexus: nexus, title: "Notes", index: index)
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault, index: index)
        let set = try makePageSet(title: "Drafts", in: coll, index: index)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = IndexUpdater(index)

        let meta = try await manager.createPage(name: "Doc", in: coll, vault: vault)
        let pageID = meta.id  // hoist before the dbQueue closures (@Sendable)
        let setID = set.id

        try await manager.movePageToSet(
            meta, from: .collection(coll, vault: vault), to: set, collection: coll, vault: vault)
        let setRow = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(setRow?["page_set_id"] as String? == setID)

        let inSet = manager.pages(in: set).first!
        try await manager.movePageOutOfSet(
            inSet, from: set, collection: coll, vault: vault, to: .vaultRoot(vault))
        let rootRow = try await index.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM pages WHERE id = ?", arguments: [pageID])
        }
        #expect(rootRow?["page_set_id"] as String? == nil)
        #expect(rootRow?["page_collection_id"] as String? == nil)
        #expect(manager.pages(in: vault).map(\.id) == [pageID])
    }

    // MARK: - Cross-Type strip regression

    @Test("Cross-Type move still strips non-shared properties after the in-vault move hoist")
    func crossTypeMoveStillStrips() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let prop = PropertyDefinition(id: "prop_only_a", name: "Status", type: .status)
        let typeA = try makePageType(nexus: nexus, title: "TypeA", properties: [prop])
        let typeB = try makePageType(nexus: nexus, title: "TypeB")
        let collA = try makePageCollection(nexus: nexus, title: "CollA", in: typeA)

        let pageID = ULID.generate()
        let fm = PageFrontmatter(
            id: pageID, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: ["prop_only_a": .status("done")], createdAt: Date()
        )
        let srcURL = NexusPaths.pageFileURL(forTitle: "Doc", in: collA.folderURL)
        try PageFile(frontmatter: fm, body: "body", title: "Doc").save(to: srcURL)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let page = PageMeta(id: pageID, title: "Doc", url: srcURL, frontmatter: fm)
        manager.pagesByCollection[collA.id] = [page]
        manager.pagesByTypeRoot[typeB.id] = []

        try await manager.movePageAcrossTypes(
            page, from: typeA, fromCollection: collA, to: typeB, toCollection: nil)

        let dstURL = NexusPaths.pageFileURL(
            forTitle: "Doc", in: NexusPaths.vaultFolderURL(forTitle: "TypeB", in: nexus))
        let loaded = try PageFile.load(from: dstURL)
        #expect(loaded.frontmatter.properties["prop_only_a"] == nil)
        #expect(manager.pagesByCollection[collA.id]?.isEmpty == true)
        #expect(manager.pagesByTypeRoot[typeB.id]?.count == 1)
    }

    // MARK: - Reorder

    @Test("reorderPages(in: set) persists page_order on the Set sidecar")
    func reorderWithinSetPersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let vault = try makePageType(nexus: nexus, title: "Notes")
        let coll = try makePageCollection(nexus: nexus, title: "Inbox", in: vault)
        let set = try makePageSet(title: "Drafts", in: coll)
        _ = try writePage(titled: "One", in: set.folderURL)
        _ = try writePage(titled: "Two", in: set.folderURL)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await manager.loadAll(for: set)
        // Two ULIDs minted in the same millisecond tie on the timestamp
        // prefix — derive the baseline instead of assuming creation order.
        let initial = manager.pages(in: set).map(\.id)
        #expect(initial.count == 2)

        manager.reorderPages(in: set, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let reordered = manager.pages(in: set).map(\.id)
        #expect(reordered == [initial[1], initial[0]])

        let sidecar = try PageSet.load(
            from: set.folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        #expect(sidecar.pageOrder == reordered)

        // A fresh load resolves the persisted order.
        let fresh = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        await fresh.loadAll(for: sidecar)
        #expect(fresh.pages(in: sidecar).map(\.id) == reordered)
    }

    // MARK: - Fixtures (mirror MovePageTests + NexusWideUniquenessTests)

    @discardableResult
    private func makePageType(
        nexus: Nexus,
        title: String,
        properties: [PropertyDefinition] = [],
        index: PommoraIndex? = nil
    ) throws -> PageType {
        let vault = PageType(
            id: ULID.generate(), title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: title, in: nexus))
        if let index { try IndexUpdater(index).upsertPageType(vault) }
        return vault
    }

    @discardableResult
    private func makePageCollection(
        nexus: Nexus,
        title: String,
        in vault: PageType,
        index: PommoraIndex? = nil
    ) throws -> PageCollection {
        let folderURL = NexusPaths.collectionFolderURL(
            forTitle: title, inVaultTitled: vault.title, in: nexus
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageCollection(coll) }
        return coll
    }

    @discardableResult
    private func makePageSet(
        title: String,
        in collection: PageCollection,
        index: PommoraIndex? = nil
    ) throws -> PageSet {
        let folderURL = collection.folderURL.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let set = PageSet(
            id: ULID.generate(), collectionID: collection.id, title: title,
            folderURL: folderURL, modifiedAt: Date()
        )
        try set.save(to: folderURL.appendingPathComponent(NexusPaths.pageSetSidecarFilename))
        if let index { try IndexUpdater(index).upsertPageSet(set) }
        return set
    }

    /// Writes a `.md` Page with proper frontmatter into `folder`; returns its id.
    private func writePage(titled title: String, in folder: URL) throws -> String {
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: fm, body: "",
            to: NexusPaths.pageFileURL(forTitle: title, in: folder))
        return id
    }
}
