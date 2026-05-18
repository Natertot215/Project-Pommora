import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("ContentManager")
struct ContentManagerTests {

    @Test("createPage writes .md with frontmatter scaffold")
    func createPage() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let pages = manager.pages(in: coll)
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Notes")

        let loaded = try PageFile.load(from: url)
        #expect(!loaded.frontmatter.id.isEmpty)
        #expect(loaded.body == "")
        #expect(loaded.frontmatter.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("createItem writes .json with empty structure")
    func createItem() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createItem(name: "Buy groceries", in: coll, vault: vault)
        let url = NexusPaths.itemFileURL(forTitle: "Buy groceries", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let items = manager.items(in: coll)
        #expect(items.count == 1)
        #expect(items.first?.title == "Buy groceries")
    }

    @Test("renamePage moves file + updates pages list")
    func renamePage() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!

        try await manager.renamePage(page, to: "Ideas", in: coll, vault: vault)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Ideas", in: coll.folderURL).path
            ))
        #expect(manager.pages(in: coll).first?.title == "Ideas")
    }

    @Test("renameItem moves file + updates items list")
    func renameItem() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createItem(name: "X", in: coll, vault: vault)
        let item = manager.items(in: coll).first!
        let oldURL = NexusPaths.itemFileURL(forTitle: "X", in: coll.folderURL)

        try await manager.renameItem(item, to: "Y", in: coll, vault: vault)
        let newURL = NexusPaths.itemFileURL(forTitle: "Y", in: coll.folderURL)

        #expect(manager.items(in: coll).first?.title == "Y")
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
    }

    @Test("updateItem persists property changes")
    func updateItem() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createItem(name: "X", in: coll, vault: vault)
        var item = manager.items(in: coll).first!
        item.description = "Updated"

        try await manager.updateItem(item, in: coll, vault: vault)
        #expect(manager.items(in: coll).first?.description == "Updated")
        let url = NexusPaths.itemFileURL(forTitle: "X", in: coll.folderURL)
        let reloaded = try Item.load(from: url)
        #expect(reloaded.description == "Updated")
    }

    @Test("deletePage + deleteItem remove files")
    func deletes() async throws {
        let (nexus, vault, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try await manager.createPage(name: "P", in: coll, vault: vault)
        try await manager.createItem(name: "I", in: coll, vault: vault)
        let page = manager.pages(in: coll).first!
        let item = manager.items(in: coll).first!
        let pageURL = NexusPaths.pageFileURL(forTitle: "P", in: coll.folderURL)
        let itemURL = NexusPaths.itemFileURL(forTitle: "I", in: coll.folderURL)

        try await manager.deletePage(page, in: coll)
        try await manager.deleteItem(item, in: coll)

        #expect(manager.pages(in: coll).isEmpty)
        #expect(manager.items(in: coll).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: pageURL.path))
        #expect(!FileManager.default.fileExists(atPath: itemURL.path))
    }

    @Test("loadAll discovers existing .md + .json in a Collection")
    func loadExisting() async throws {
        let (nexus, _, coll, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        try FixtureFiles.write(
            "---\nid: 01HPRE\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "Pre", in: coll.folderURL)
        )
        try Item(
            id: "01HITEM", title: "Pre", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(), modifiedAt: Date()
        ).save(to: NexusPaths.itemFileURL(forTitle: "Pre-item", in: coll.folderURL))

        await manager.loadAll(for: coll)
        #expect(manager.pages(in: coll).count == 1)
        #expect(manager.items(in: coll).count == 1)
    }

    private func setup() async throws -> (Nexus, Vault, Collection, ContentManager) {
        let nexus = try TempNexus.make()
        let vault = Vault(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = Collection(
            id: ULID.generate(),
            vaultID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = ContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, coll, manager)
    }
}
