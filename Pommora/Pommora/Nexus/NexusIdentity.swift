//
//  NexusIdentity.swift
//  Pommora
//

import Foundation

/// Vault-portable identity persisted at `<nexus>/.nexus/nexus.json`.
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
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NexusIdentity.self, from: data)
    }

    /// Atomically writes identity as pretty-printed JSON with sorted keys.
    /// ISO-8601 dates for human readability and cross-platform parsing.
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }
}
