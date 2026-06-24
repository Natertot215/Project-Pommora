import Foundation

/// User-creatable sidebar sections that group Collections — navigation-only
/// (no on-disk collection move; PagesV2 P9, band 3).
///
/// Single-membership (ratified decision #6): a collection sits in at most one
/// user section. Ungrouped collections render in the default Collections section.
/// Deleting a section ungroups its collections (they return to the default
/// section) — no collection data is touched.
///
/// On disk: `<nexus>/.nexus/sidebar-sections.json`.
struct SidebarSectionsConfig: Codable, Equatable, Hashable, Sendable {
    struct Section: Codable, Equatable, Hashable, Identifiable, Sendable {
        let id: String  // ULID
        var label: String  // user-renamable inline
        var collectionIDs: [String]  // PageCollection IDs, in display order
    }

    var sections: [Section] = []

    /// Every collection ID claimed by any user section. The default Collections
    /// section renders only collections NOT in this set. Dangling IDs (collection
    /// deleted after grouping) stay in the config and skip-render in the
    /// UI — the config is not self-healed.
    var groupedCollectionIDs: Set<String> {
        Set(sections.flatMap(\.collectionIDs))
    }

    static func defaultSeed() -> SidebarSectionsConfig {
        SidebarSectionsConfig(sections: [])
    }
}
