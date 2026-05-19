// NexusState.swift
import Foundation

/// Per-nexus app state, persisted at <nexus>/.nexus/state.json.
/// Versioned; decode tolerates missing keys (forward-compat with
/// future v0.2 patches that may add new top-level fields, and
/// backwards-compat with future schema bumps).
struct NexusState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var recents: [EntityStateRef] = []
    var favorites: [EntityStateRef] = []
    var cursor: Int = 0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, recents, favorites, cursor
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.recents = try c.decodeIfPresent([EntityStateRef].self, forKey: .recents) ?? []
        self.favorites = try c.decodeIfPresent([EntityStateRef].self, forKey: .favorites) ?? []
        self.cursor = try c.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(recents, forKey: .recents)
        try c.encode(favorites, forKey: .favorites)
        try c.encode(cursor, forKey: .cursor)
    }
}
