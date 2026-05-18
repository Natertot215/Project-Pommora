import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("VaultManager")
struct VaultManagerTests {

    @Test("createVault writes folder + _vault.json")
    func createVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: "folder")
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: "Planner", in: nexus)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: meta.path))
        #expect(manager.vaults.count == 1)
        #expect(manager.vaults.first?.title == "Planner")
    }

    @Test("createCollection creates folder inside Vault")
    func createCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)

        let folder = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: folder.path))
        let cols = manager.collections(in: vault)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Tasks")
    }

    @Test("renameVault renames folder + updates collection paths")
    func renameVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)

        try await manager.renameVault(vault, to: "Schedule")
        let newFolder = NexusPaths.vaultFolderURL(forTitle: "Schedule", in: nexus)
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        // Collection still present under new vault folder
        let renamedVault = manager.vaults.first!
        let cols = manager.collections(in: renamedVault)
        #expect(cols.count == 1)
        #expect(cols.first?.title == "Tasks")
    }

    @Test("deleteVault removes folder + collections")
    func deleteVault() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)

        try await manager.deleteVault(vault)
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.vaults.isEmpty)
    }

    @Test("loadAll skips top-level folders without _vault.json (cosmetic dirs)")
    func skipCosmeticFolders() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Create a top-level folder that ISN'T a vault
        try FileManager.default.createDirectory(
            at: nexus.rootURL.appendingPathComponent("NotAVault", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()
        #expect(manager.vaults.isEmpty)
    }

    @Test("renameCollection moves the folder")
    func renameCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)
        let coll = manager.collections(in: vault).first!

        try await manager.renameCollection(coll, to: "To-dos")
        let newFolder = NexusPaths.collectionFolderURL(
            forTitle: "To-dos", inVaultTitled: "Planner", in: nexus
        )
        #expect(FileManager.default.fileExists(atPath: newFolder.path))
        #expect(manager.collections(in: vault).first?.title == "To-dos")
    }

    @Test("deleteCollection removes folder")
    func deleteCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = VaultManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createVault(name: "Planner", icon: nil)
        let vault = manager.vaults.first!
        try await manager.createCollection(name: "Tasks", inVault: vault)
        let coll = manager.collections(in: vault).first!

        try await manager.deleteCollection(coll)
        let folder = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(manager.collections(in: vault).isEmpty)
    }
}
