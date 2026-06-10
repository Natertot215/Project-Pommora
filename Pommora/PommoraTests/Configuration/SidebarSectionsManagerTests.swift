import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("SidebarSectionsManager")
struct SidebarSectionsManagerTests {

    @Test("load seeds empty sections and first-writes the file")
    func seedsEmpty() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        #expect(m.config.sections.isEmpty)
        #expect(m.pendingError == nil)
        #expect(Filesystem.fileExists(at: NexusPaths.sidebarSectionsURL(in: nexus)))
    }

    @Test("save/reload round-trips sections")
    func roundTrip() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        let section = try await m.createSection(label: "Work")
        try await m.moveVault(id: "vault-1", toSection: section.id)

        let reloaded = SidebarSectionsManager(nexus: nexus)
        await reloaded.load()
        #expect(reloaded.config == m.config)
        #expect(reloaded.config.sections.count == 1)
        #expect(reloaded.config.sections[0].label == "Work")
        #expect(reloaded.config.sections[0].vaultIDs == ["vault-1"])
    }

    @Test("single membership — moving a vault into section B removes it from section A")
    func singleMembership() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        let a = try await m.createSection(label: "A")
        let b = try await m.createSection(label: "B")
        try await m.moveVault(id: "vault-1", toSection: a.id)
        try await m.moveVault(id: "vault-1", toSection: b.id)
        #expect(m.config.sections.first(where: { $0.id == a.id })?.vaultIDs == [])
        #expect(m.config.sections.first(where: { $0.id == b.id })?.vaultIDs == ["vault-1"])
        #expect(m.section(containing: "vault-1")?.id == b.id)
    }

    @Test("moving a vault into its own section is idempotent (one entry, no duplicate)")
    func moveIdempotent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        let a = try await m.createSection(label: "A")
        try await m.moveVault(id: "vault-1", toSection: a.id)
        try await m.moveVault(id: "vault-1", toSection: a.id)
        #expect(m.config.sections.first(where: { $0.id == a.id })?.vaultIDs == ["vault-1"])
    }

    @Test("remove from sections returns the vault to the default section")
    func removeUngroups() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        let a = try await m.createSection(label: "A")
        try await m.moveVault(id: "vault-1", toSection: a.id)
        try await m.removeVaultFromSections(id: "vault-1")
        #expect(m.config.groupedVaultIDs.isEmpty)
        #expect(m.section(containing: "vault-1") == nil)
        // The (now empty) section itself survives.
        #expect(m.config.sections.map(\.id) == [a.id])
    }

    @Test("delete section ungroups its vaults")
    func deleteUngroups() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        let a = try await m.createSection(label: "A")
        let b = try await m.createSection(label: "B")
        try await m.moveVault(id: "vault-1", toSection: a.id)
        try await m.moveVault(id: "vault-2", toSection: b.id)
        try await m.deleteSection(id: a.id)
        #expect(m.config.sections.map(\.id) == [b.id])
        #expect(m.config.groupedVaultIDs == ["vault-2"])
        #expect(m.section(containing: "vault-1") == nil)
    }

    @Test("rename section persists across reload")
    func renamePersists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        let a = try await m.createSection(label: "New Section")
        try await m.renameSection(id: a.id, to: "Archive")
        let reloaded = SidebarSectionsManager(nexus: nexus)
        await reloaded.load()
        #expect(reloaded.config.sections.first(where: { $0.id == a.id })?.label == "Archive")
    }

    @Test("dangling vault IDs survive load and stay grouped (skip-render is the UI policy)")
    func danglingIDsPreserved() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Simulate a config left behind by a deleted vault: the ID lingers.
        let stale = SidebarSectionsConfig(sections: [
            .init(id: "s1", label: "Stuff", vaultIDs: ["dead-vault", "live-vault"])
        ])
        try AtomicJSON.write(stale, to: NexusPaths.sidebarSectionsURL(in: nexus))

        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        // Config is NOT self-healed — the dangling ID is preserved and the
        // vault stays out of the default section; the sidebar skip-renders it.
        #expect(m.config.sections.first?.vaultIDs == ["dead-vault", "live-vault"])
        #expect(m.config.groupedVaultIDs.contains("dead-vault"))
        // Mutations still work around the dangling entry.
        try await m.removeVaultFromSections(id: "live-vault")
        #expect(m.config.sections.first?.vaultIDs == ["dead-vault"])
    }

    @Test("mutations targeting a nonexistent section are no-ops")
    func missingSectionNoOps() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let m = SidebarSectionsManager(nexus: nexus)
        await m.load()
        try await m.moveVault(id: "vault-1", toSection: "nope")
        try await m.renameSection(id: "nope", to: "X")
        try await m.deleteSection(id: "nope")
        #expect(m.config == SidebarSectionsConfig.defaultSeed())
    }
}
