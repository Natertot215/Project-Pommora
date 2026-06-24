//
//  NexusIdentity.swift
//  Pommora
//

import Foundation

/// Collection-portable identity persisted at `<nexus>/.nexus/nexus.json`.
///
/// Holds the nexus's stable ULID and creation timestamp. Travels with the
/// nexus folder if the user moves it across machines via cloud sync — never
/// holds machine-specific data like security-scoped bookmarks (those live
/// in app-level `state.json` under Application Support).
struct NexusIdentity: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var createdAt: Date

    init(schemaVersion: Int = 1, id: String, createdAt: Date = .now) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
    }
}

extension NexusIdentity {
    /// Loads identity from the JSON file at the given URL. Throws if missing
    /// or malformed — caller decides how to handle (e.g. offer re-init for
    /// corruption).
    static func load(from url: URL) throws -> NexusIdentity {
        try AtomicJSON.decode(NexusIdentity.self, from: url)
    }

    /// Atomically writes identity as pretty-printed JSON via AtomicJSON.
    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
