// NexusState.swift
import Foundation

/// Per-nexus app state, persisted at <nexus>/.nexus/state.json.
/// Versioned; decode tolerates missing keys (forward-compat with
/// future v0.2 patches that may add new top-level fields, and
/// backwards-compat with future schema bumps).
///
/// Backward-compat note: the `favorites` key was renamed to `pinned` at
/// v0.2.7.2.1. The decoder still accepts the legacy `favorites` key so
/// state.json files written before the rename rehydrate cleanly; the
/// encoder only writes `pinned`, so the legacy key disappears on first save.
struct NexusState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var recents: [EntityStateRef] = []
    var pinned: [EntityStateRef] = []
    var cursor: Int = 0

    // Top-level sidebar order (v0.2.8.0). All nil until the user reorders that
    // section's siblings; missing entries fall through to OrderResolver's
    // alphabetic tail.
    var spaceOrder: [String]?
    var topicOrder: [String]?
    var vaultOrder: [String]?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case recents
        case pinned
        case favoritesLegacy = "favorites"
        case cursor
        case spaceOrder = "space_order"
        case topicOrder = "topic_order"
        case vaultOrder = "vault_order"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.recents = try c.decodeIfPresent([EntityStateRef].self, forKey: .recents) ?? []
        self.pinned =
            try c.decodeIfPresent([EntityStateRef].self, forKey: .pinned)
            ?? c.decodeIfPresent([EntityStateRef].self, forKey: .favoritesLegacy)
            ?? []
        self.cursor = try c.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
        self.spaceOrder = try c.decodeIfPresent([String].self, forKey: .spaceOrder)
        self.topicOrder = try c.decodeIfPresent([String].self, forKey: .topicOrder)
        self.vaultOrder = try c.decodeIfPresent([String].self, forKey: .vaultOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(recents, forKey: .recents)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(cursor, forKey: .cursor)
        try c.encodeIfPresent(spaceOrder, forKey: .spaceOrder)
        try c.encodeIfPresent(topicOrder, forKey: .topicOrder)
        try c.encodeIfPresent(vaultOrder, forKey: .vaultOrder)
    }
}
