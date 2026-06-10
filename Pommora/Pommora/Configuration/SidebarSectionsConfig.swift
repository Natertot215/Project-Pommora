import Foundation

/// User-creatable sidebar sections that group Vaults — navigation-only
/// (no on-disk vault move; PagesV2 P9, band 3).
///
/// Single-membership (ratified decision #6): a vault sits in at most one
/// user section. Ungrouped vaults render in the default Vaults section.
/// Deleting a section ungroups its vaults (they return to the default
/// section) — no vault data is touched.
///
/// On disk: `<nexus>/.nexus/sidebar-sections.json`.
struct SidebarSectionsConfig: Codable, Equatable, Hashable, Sendable {
    struct Section: Codable, Equatable, Hashable, Identifiable, Sendable {
        let id: String  // ULID
        var label: String  // user-renamable inline
        var vaultIDs: [String]  // PageType IDs, in display order
    }

    var sections: [Section] = []

    /// Every vault ID claimed by any user section. The default Vaults
    /// section renders only vaults NOT in this set. Dangling IDs (vault
    /// deleted after grouping) stay in the config and skip-render in the
    /// UI — the config is not self-healed.
    var groupedVaultIDs: Set<String> {
        Set(sections.flatMap(\.vaultIDs))
    }

    static func defaultSeed() -> SidebarSectionsConfig {
        SidebarSectionsConfig(sections: [])
    }
}
