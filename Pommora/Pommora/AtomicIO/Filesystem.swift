import Foundation

/// Folder + file primitives used by every entity manager.
///
/// Discipline:
/// - Every multi-step operation (folder + metadata file) rolls back on failure.
/// - All paths must be inside the active nexus's security-scoped resource scope
///   held by `NexusManager` — managers MUST NOT call `startAccessingSecurityScopedResource`
///   themselves.
enum Filesystem {

    // MARK: - Folder primitives

    static func createFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Atomic on same-volume rename (nexus contents are always single-volume).
    static func renameFolder(from oldURL: URL, to newURL: URL) throws {
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    static func deleteFolder(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func folderExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    // MARK: - File primitives

    static func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func fileExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    static func renameFile(from oldURL: URL, to newURL: URL) throws {
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    // MARK: - Two-step folder+metadata atomicity

    /// Creates `folderURL`, then writes `metadata` (a `Codable` value) to `metadataURL`.
    /// If the metadata write fails, the folder is deleted before the error propagates.
    ///
    /// Used by Topic + Vault creation flows (Topic = folder + `_topic.json`;
    /// Vault = folder + `_vault.json`).
    static func createFolderWithMetadata<T: Codable>(
        folderURL: URL,
        metadataURL: URL,
        metadata: T
    ) throws {
        try createFolder(at: folderURL)
        do {
            try AtomicJSON.write(metadata, to: metadataURL)
        } catch {
            try? deleteFolder(at: folderURL)
            throw error
        }
    }

    // MARK: - Directory enumeration

    /// Returns immediate children of `folderURL` matching `predicate` (typically by extension).
    /// Returns `[]` if the folder doesn't exist.
    static func children(
        of folderURL: URL,
        where predicate: (URL) -> Bool = { _ in true }
    ) throws -> [URL] {
        guard folderExists(at: folderURL) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter(predicate)
    }

    /// Returns immediate child folders (not files).
    static func childFolders(of folderURL: URL) throws -> [URL] {
        try children(of: folderURL) { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }
}
