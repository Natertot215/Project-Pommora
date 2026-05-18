import Foundation
import Testing

@testable import Pommora

/// Vault-root Content (Pages + Items sitting directly in a Vault folder, not
/// inside a Collection sub-folder). Mirrors ContentManagerTests but uses the
/// parallel `(inVaultRoot:)` overloads + `pages(in: vault)` / `items(in: vault)`
/// accessors.
@MainActor
@Suite("ContentManager vault-root")
struct ContentManagerVaultRootTests {

    @Test("loadAll for an empty vault root yields empty arrays")
    func loadAllForVaultEmpty() async throws {
        let (nexus, vault, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        await manager.loadAll(for: vault)
        #expect(manager.pages(in: vault).isEmpty)
        #expect(manager.items(in: vault).isEmpty)
    }

    @Test("loadAll for a vault with .md files at root populates pagesByVaultRoot")
    func loadAllForVaultWithPages() async throws {
        let (nexus, vault, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        try FixtureFiles.write(
            "---\nid: 01HPA\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "Alpha", in: folder)
        )
        try FixtureFiles.write(
            "---\nid: 01HPB\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "Beta", in: folder)
        )

        await manager.loadAll(for: vault)
        let titles = manager.pages(in: vault).map(\.title)
        #expect(titles.count == 2)
        #expect(titles == ["Alpha", "Beta"])  // sorted
    }

    @Test("loadAll for a vault ignores Collection sub-folder contents")
    func loadAllForVaultIgnoresCollectionContents() async throws {
        let (nexus, vault, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // One Page at vault root
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        try FixtureFiles.write(
            "---\nid: 01HROOT\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "RootPage", in: vaultFolder)
        )

        // One Collection sub-folder containing one Page
        let collFolder = NexusPaths.collectionFolderURL(
            forTitle: "Inner", inVaultTitled: vault.title, in: nexus
        )
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = Pommora.Collection(
            id: ULID.generate(),
            vaultID: vault.id,
            title: "Inner",
            folderURL: collFolder,
            modifiedAt: Date()
        )
        // Sidecar so Vault discovery would treat this as a real Collection
        try coll.save(to: collFolder.appendingPathComponent("_collection.json"))
        try FixtureFiles.write(
            "---\nid: 01HINNER\ncreated_at: 2025-01-01T00:00:00Z\n---\n\nbody\n",
            to: NexusPaths.pageFileURL(forTitle: "InnerPage", in: collFolder)
        )

        await manager.loadAll(for: vault)
        await manager.loadAll(for: coll)

        let rootPages = manager.pages(in: vault)
        let collPages = manager.pages(in: coll)
        #expect(rootPages.count == 1)
        #expect(rootPages.first?.title == "RootPage")
        #expect(collPages.count == 1)
        #expect(collPages.first?.title == "InnerPage")
    }

    @Test("createPage in vault root writes .md + updates pages(in: vault)")
    func createPageInVaultRoot() async throws {
        let (nexus, vault, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        _ = try await manager.createPage(name: "Notes", inVaultRoot: vault)
        let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: folder)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let pages = manager.pages(in: vault)
        #expect(pages.count == 1)
        #expect(pages.first?.title == "Notes")

        let loaded = try PageFile.load(from: url)
        #expect(!loaded.frontmatter.id.isEmpty)
        #expect(loaded.body == "")
    }

    @Test("renamePage in vault root moves file + updates pages(in: vault)")
    func renamePageInVaultRoot() async throws {
        let (nexus, vault, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        _ = try await manager.createPage(name: "Notes", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!

        try await manager.renamePage(page, to: "Ideas", inVaultRoot: vault)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: folder).path
            ))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Ideas", in: folder).path
            ))
        #expect(manager.pages(in: vault).first?.title == "Ideas")
    }

    @Test("deletePage in vault root removes file + updates pages(in: vault)")
    func deletePageInVaultRoot() async throws {
        let (nexus, vault, manager) = try await setup()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.vaultFolderURL(forTitle: vault.title, in: nexus)
        _ = try await manager.createPage(name: "Notes", inVaultRoot: vault)
        let page = manager.pages(in: vault).first!

        try await manager.deletePage(page, inVaultRoot: vault)
        #expect(
            !FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: folder).path
            ))
        #expect(manager.pages(in: vault).isEmpty)
    }

    // MARK: - Setup

    private func setup() async throws -> (Nexus, Vault, ContentManager) {
        let nexus = try TempNexus.make()
        let vault = Vault(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let manager = ContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, manager)
    }
}
