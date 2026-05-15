//
//  AppState.swift
//  Pommora
//

import Foundation

/// Machine-specific app state that does not belong inside any individual nexus.
///
/// Persisted as a pretty-printed JSON file at:
///   `~/Library/Application Support/com.nathantaichman.Pommora/state.json`
///
/// Holds a single value for v0.1: the security-scoped bookmark of the
/// last-opened nexus. Future fields (recent nexuses, last window frame,
/// etc.) extend this same shape.
///
/// Vault-portable per-nexus state (open tabs, sidebar collapsed state)
/// lives separately at `<nexus>/.nexus/state.json` and is the concern
/// of a future v0.2+ type — not this one.
struct AppState: Codable, Equatable {
    var schemaVersion: Int
    var lastNexusBookmark: Data?

    init(schemaVersion: Int = 1, lastNexusBookmark: Data? = nil) {
        self.schemaVersion = schemaVersion
        self.lastNexusBookmark = lastNexusBookmark
    }
}

extension AppState {
    /// Loads state from a JSON file at the given URL.
    /// Throws if the file is missing — callers decide whether that means
    /// "first launch, default state" or a hard error.
    static func load(from url: URL) throws -> AppState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppState.self, from: data)
    }

    /// Atomically writes state to a JSON file at the given URL.
    /// Pretty-printed with sorted keys for human inspectability and
    /// git-friendly diffs (relevant if a user puts App Support under VCS
    /// for backup, which is unusual but possible).
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }
}
