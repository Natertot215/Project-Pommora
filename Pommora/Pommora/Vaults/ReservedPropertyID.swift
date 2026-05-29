import Foundation

/// Catalog of reserved property IDs. Built-in (Pommora-managed) properties use the `_` prefix
/// (`_id`, `_status`, `_tier1`, …); user-defined properties use the `prop_` prefix minted by
/// `mintUserPropertyID()`. The schema editor must block user attempts to claim a reserved ID.
///
/// Property display *names* are unrestricted — a user may rename a property to "_status"
/// freely. Only the ID field is reserved.
enum ReservedPropertyID {
    // MARK: - Named constants

    // `nonisolated`: pure immutable `String` constants, read from both @MainActor
    // (schema editor / validators) and nonisolated contexts (the index layer's
    // off-actor GRDB-write closures — e.g. IndexBuilder's tier-relations emit).
    // The project default isolation is @MainActor, so these opt out explicitly.
    nonisolated static let id          = "_id"
    nonisolated static let createdAt   = "_created_at"
    nonisolated static let modifiedAt  = "_modified_at"
    nonisolated static let status      = "_status"
    nonisolated static let type        = "_type"
    nonisolated static let tier1       = "_tier1"
    nonisolated static let tier2       = "_tier2"
    nonisolated static let tier3       = "_tier3"
    nonisolated static let wikilinks   = "_wikilinks"

    // MARK: - Catalog

    /// All reserved IDs Pommora knows about as of v0.3.0.
    nonisolated static let all: Set<String> = [
        id, createdAt, modifiedAt,
        status,
        type,
        tier1, tier2, tier3,
        wikilinks,
    ]

    // MARK: - Helpers

    /// True iff `id` is in the reserved catalog. Used by the schema-editor validator.
    nonisolated static func isReserved(_ id: String) -> Bool {
        all.contains(id)
    }

    /// Mint a fresh user-defined property ID using the `prop_<ulid>` scheme.
    static func mintUserPropertyID() -> String {
        "prop_\(ULID.generate())"
    }
}
