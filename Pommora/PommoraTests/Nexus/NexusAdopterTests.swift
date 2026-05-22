import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("NexusAdopter")
struct NexusAdopterTests {

    // MARK: - scan

    @Test("scan returns empty plan for an empty folder")
    func scanEmpty() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.vaults.isEmpty)
        #expect(plan.collections.isEmpty)
        #expect(plan.pagesPreviewCount == 0)
        #expect(plan.itemsPreviewCount == 0)
        #expect(!plan.hasAnythingToAdopt)
    }

    @Test("scan proposes Vault for top-level folder without _schema.json")
    func scanProposesVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.vaults.count == 1)
        #expect(plan.vaults.first?.title == "Projects")
        #expect(plan.vaults.first?.folderURL.lastPathComponent == "Projects")
    }

    @Test("scan skips top-level folder that already has _schema.json (idempotent)")
    func scanSkipsExistingVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: metaURL
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.vaults.isEmpty)
    }

    @Test("scan proposes Collection for sub-folder without _schema.json")
    func scanProposesCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.collections.count == 1)
        #expect(plan.collections.first?.title == "Active")
        #expect(plan.collections.first?.vaultFolderURL.lastPathComponent == "Projects")
    }

    @Test("scan skips sub-folder that already has _schema.json")
    func scanSkipsExistingCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HC","vault_id":"01HV","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: sub.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        // Vault is still proposed (no _schema.json on the vault folder yet),
        // but the existing sub-folder sidecar means the collection is NOT re-proposed.
        #expect(plan.vaults.count == 1)
        #expect(plan.collections.isEmpty)
    }

    @Test("scan excludes hidden folders, underscore-prefixed, Agenda, node_modules")
    func scanExclusions() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let root = nexus.rootURL
        let excluded = [".git", ".obsidian", "_internal", "Agenda", "node_modules"]
        let included = ["Real"]
        for name in excluded + included {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.vaults.count == 1)
        #expect(plan.vaults.first?.title == "Real")
        let skippedNames = Set(plan.skippedTopLevel.map { $0.lastPathComponent })
        // Hidden folders may be skipped by Filesystem.skipsHiddenFiles; the
        // non-hidden excluded names should still appear in skipped.
        #expect(skippedNames.contains("Agenda"))
        #expect(skippedNames.contains("node_modules"))
        #expect(skippedNames.contains("_internal"))
    }

    @Test("scan counts .md and .json descendants recursively")
    func scanCountsRecursive() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        let coll = vault.appendingPathComponent("Active", isDirectory: true)
        let deep = coll.appendingPathComponent("deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        // 2 md files: 1 at vault root, 1 deep inside Collection sub-folder
        try FixtureFiles.write("# Top", to: vault.appendingPathComponent("Top.md"))
        try FixtureFiles.write("# Deep", to: deep.appendingPathComponent("Deep.md"))
        // 1 json file inside the Collection
        try FixtureFiles.writeJSON(
            #"{"id":"01HI","created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z","description":"","tier1":[],"tier2":[],"tier3":[],"properties":{}}"#,
            to: coll.appendingPathComponent("Item.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.pagesPreviewCount == 2)
        #expect(plan.itemsPreviewCount == 1)
    }

    // MARK: - apply

    @Test("apply writes _schema.json into existing folders")
    func applyWritesVaultSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: metaURL.path))

        let vault = try Vault.load(from: metaURL)
        #expect(vault.title == "Projects")
        #expect(!vault.id.isEmpty)
    }

    @Test("apply writes Collection _schema.json with parent vault's id")
    func applyLinksCollectionToVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let vaultMetaURL = vault.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let collMetaURL = sub.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let vaultModel = try Vault.load(from: vaultMetaURL)
        let collModel = try Collection.load(from: collMetaURL)

        #expect(collModel.vaultID == vaultModel.id)
        #expect(collModel.title == "Active")
    }

    @Test("scan+apply is idempotent — second pass writes nothing new")
    func idempotent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan1 = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan1)

        let plan2 = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan2.vaults.isEmpty)
        #expect(plan2.collections.isEmpty)
        #expect(!plan2.hasAnythingToAdopt)
    }

    @Test("apply preserves vault id across re-load")
    func vaultIDStable() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let first = try Vault.load(from: metaURL)
        let second = try Vault.load(from: metaURL)
        #expect(first.id == second.id)
    }
}
