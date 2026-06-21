import Foundation
import Observation

/// Loads, persists, and mutates the user sidebar sections that group Vaults
/// (PagesV2 P9). Mirrors `SavedConfigManager`: `load()` seeds + first-writes
/// the default config, `save()` writes atomically, and every failure lands in
/// `pendingError` for the sidebar toast.
///
/// All mutations enforce single-membership (ratified decision #6): moving a
/// vault into a section strips it from every other section in the same config
/// write — one mutation, one save.
@MainActor
@Observable
final class SidebarSectionsManager {
    var config: SidebarSectionsConfig = SidebarSectionsConfig.defaultSeed()
    var pendingError: (any Error)?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func load() async {
        do {
            let url = NexusPaths.sidebarSectionsURL(in: nexus)
            try NexusPaths.ensureDirectoryExists(url.deletingLastPathComponent())
            if Filesystem.fileExists(at: url) {
                config = try AtomicJSON.decode(SidebarSectionsConfig.self, from: url)
            } else {
                config = SidebarSectionsConfig.defaultSeed()
                try AtomicJSON.write(config, to: url)
            }
            pendingError = nil
        } catch {
            pendingError = error
        }
    }

    func save() async throws {
        do {
            let url = NexusPaths.sidebarSectionsURL(in: nexus)
            try AtomicJSON.write(config, to: url)
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Section mutations (each persists via save())

    /// Appends a new empty section and persists. Returns the created section
    /// so callers can flip it into inline-rename mode (`CreateWithInlineEdit`).
    @discardableResult
    func createSection(label: String) async throws -> SidebarSectionsConfig.Section {
        let section = SidebarSectionsConfig.Section(
            id: ULID.generate(), label: label, vaultIDs: []
        )
        config.sections.append(section)
        try await save()
        return section
    }

    func renameSection(id: String, to label: String) async throws {
        guard let i = config.sections.firstIndex(where: { $0.id == id }) else { return }
        config.sections[i].label = label
        try await save()
    }

    /// Removes the section. Its vaults return to the default Vaults section
    /// implicitly — membership lived only in the deleted record
    /// (navigation-only; no vault data is touched).
    func deleteSection(id: String) async throws {
        guard config.sections.contains(where: { $0.id == id }) else { return }
        config.sections.removeAll { $0.id == id }
        try await save()
    }

    /// Single-membership move modeled as ONE mutation: strips `vaultID` from
    /// every section, then appends it to the target — so moving A→B removes
    /// the vault from A and adds it to B in a single config write.
    func moveVault(id vaultID: String, toSection sectionID: String) async throws {
        guard let target = config.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        for i in config.sections.indices {
            config.sections[i].vaultIDs.removeAll { $0 == vaultID }
        }
        config.sections[target].vaultIDs.append(vaultID)
        try await save()
    }

    /// "Remove from Section" — strips `vaultID` from every section so the
    /// vault returns to the default Vaults section.
    func removeVaultFromSections(id vaultID: String) async throws {
        guard config.groupedVaultIDs.contains(vaultID) else { return }
        for i in config.sections.indices {
            config.sections[i].vaultIDs.removeAll { $0 == vaultID }
        }
        try await save()
    }

    /// The user section currently holding `vaultID`, if any (single-membership
    /// guarantees at most one).
    func section(containing vaultID: String) -> SidebarSectionsConfig.Section? {
        config.sections.first { $0.vaultIDs.contains(vaultID) }
    }
}
