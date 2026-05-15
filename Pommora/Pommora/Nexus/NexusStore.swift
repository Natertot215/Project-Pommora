//
//  NexusStore.swift
//  Pommora
//

import Foundation

/// Pure path-resolution functions for Pommora's Application Support footprint.
///
/// Layout:
/// ```
/// ~/Library/Application Support/
///   <bundle-id>/                      ← pommoraAppDir()
///     state.json                      ← appStateURL()
///     nexuses/
///       <nexus-id>/                   ← nexusDataDir(nexusID:)
///         pommora.db                  ← databaseURL(nexusID:) [reserved in v0.1; created in v0.2+]
///         cache/                      ← future
/// ```
///
/// Per-nexus subdirectories are marked `isExcludedFromBackup = true` so backup
/// systems skip the regeneratable index. The vault folder itself stays purely
/// canonical content; this directory is the app's private mirror/cache space.
enum NexusStore {
    enum StoreError: Swift.Error {
        case bundleIdentifierMissing
    }

    /// Returns the user's Application Support directory URL, creating it if needed.
    static func applicationSupportDir() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    /// Pommora's namespaced subdirectory inside Application Support, keyed by
    /// the bundle identifier. Created lazily.
    static func pommoraAppDir() throws -> URL {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw StoreError.bundleIdentifierMissing
        }
        let dir = try applicationSupportDir()
            .appendingPathComponent(bundleID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// URL for the app-level `state.json` (machine-specific state — bookmark,
    /// future recent-nexus list, future last-window-frame, etc.).
    static func appStateURL() throws -> URL {
        try pommoraAppDir().appendingPathComponent("state.json", isDirectory: false)
    }

    /// Per-nexus data directory under Application Support. Created lazily and
    /// marked excluded from backup on first creation (one-time cost).
    static func nexusDataDir(nexusID: String) throws -> URL {
        let dir = try pommoraAppDir()
            .appendingPathComponent("nexuses", isDirectory: true)
            .appendingPathComponent(nexusID, isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try markExcludedFromBackup(dir)
        }
        return dir
    }

    /// SQLite index path for a given nexus. v0.1 reserves the path only; the
    /// database file itself is created in v0.2 by the GRDB layer.
    static func databaseURL(nexusID: String) throws -> URL {
        try nexusDataDir(nexusID: nexusID)
            .appendingPathComponent("pommora.db", isDirectory: false)
    }

    private static func markExcludedFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}
