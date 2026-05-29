import Foundation

/// Catalog of reserved property IDs. Built-in (Pommora-managed) properties use the `_` prefix
/// (`_id`, `_status`, `_tier1`, …); user-defined properties use the `prop_` prefix minted by
/// `mintUserPropertyID()`. The schema editor must block user attempts to claim a reserved ID.
///
/// Property display *names* are unrestricted — a user may rename a property to "_status"
/// freely. Only the ID field is reserved.
enum ReservedPropertyID {
    // MARK: - Named constants

    static let id          = "_id"
    static let createdAt   = "_created_at"
    static let modifiedAt  = "_modified_at"
    static let status      = "_status"
    static let type        = "_type"
    static let tier1       = "_tier1"
    static let tier2       = "_tier2"
    static let tier3       = "_tier3"
    static let wikilinks   = "_wikilinks"

    // MARK: - Catalog

    /// All reserved IDs Pommora knows about as of v0.3.0.
    static let all: Set<String> = [
        id, createdAt, modifiedAt,
        status,
        type,
        tier1, tier2, tier3,
        wikilinks,
    ]

    // MARK: - Helpers

    /// True iff `id` is in the reserved catalog. Used by the schema-editor validator.
    static func isReserved(_ id: String) -> Bool {
        all.contains(id)
    }

    /// Mint a fresh user-defined property ID using the `prop_<ulid>` scheme.
    static func mintUserPropertyID() -> String {
        "prop_\(ULID.generate())"
    }
}
