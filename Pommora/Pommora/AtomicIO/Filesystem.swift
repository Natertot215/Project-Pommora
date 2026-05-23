import Foundation

/// Errors thrown by `Filesystem` primitives.
enum FilesystemError: LocalizedError {
    /// Raised by `moveToTrash` when the source URL doesn't sit under the
    /// nexus root — we refuse to relocate paths outside the user's nexus.
    case sourceNotInNexus(source: URL, nexus: URL)

    var errorDescription: String? {
        switch self {
        case .sourceNotInNexus(let source, let nexus):
            return "Cannot move to trash: \(source.path) is not inside nexus root \(nexus.path)."
        }
    }
}

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
    /// Used by Topic + PageType + ItemType creation flows (Topic = folder +
    /// `_topic.json`; PageType = folder + `_pagetype.json`;
    /// ItemType = folder + `_itemtype.json`).
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

    /// Writes a metadata sidecar into an already-existing folder.
    /// Counterpart to `createFolderWithMetadata` for the adoption flow:
    /// the folder is the user's pre-existing content, so we MUST NOT touch
    /// the folder itself — only drop the sidecar JSON next to it.
    static func writeMetadataIntoExistingFolder<T: Codable>(
        metadataURL: URL,
        metadata: T
    ) throws {
        try AtomicJSON.write(metadata, to: metadataURL)
    }

    // MARK: - Trash (recoverable deletes)

    /// Move a file or folder to the nexus's `.trash//` directory, preserving
    /// its relative path under the nexus root. If a previously-deleted entry
    /// already exists at the same trash path, the new entry is suffixed with
    /// a timestamp (e.g. `Notes.20260518-093215.md`) to avoid collision.
    ///
    /// Returns the URL the item was moved to (useful for tests + future
    /// "Recover deleted" UI).
    @discardableResult
    static func moveToTrash(_ source: URL, in nexus: Nexus) throws -> URL {
        let trashRoot = NexusPaths.trashDir(in: nexus)

        // Compute the relative path under nexus root (preserves user's folder structure inside .trash).
        guard let relativePath = source.path.removingPrefix(nexus.rootURL.path + "/") else {
            throw FilesystemError.sourceNotInNexus(source: source, nexus: nexus.rootURL)
        }
        let proposedDest = trashRoot.appendingPathComponent(relativePath)

        // Ensure parent directories exist in .trash
        let proposedParent = proposedDest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: proposedParent, withIntermediateDirectories: true)

        // Collision resolution via timestamp suffix
        let finalDest =
            FileManager.default.fileExists(atPath: proposedDest.path)
            ? suffixedWithTimestamp(proposedDest)
            : proposedDest

        try FileManager.default.moveItem(at: source, to: finalDest)
        return finalDest
    }

    /// Inserts a `.YYYYMMDD-HHMMSS-XXXX` stamp before the file extension (or at
    /// the end of the path component if there's no extension — for folders).
    ///
    /// The timestamp is in UTC for cross-timezone determinism (trash filenames
    /// sort consistently regardless of which timezone the user was in at delete
    /// time). The 4-char hex discriminator (UUID prefix) guarantees uniqueness
    /// for multiple deletes of the same path within the same wall-clock second
    /// — safe today (managers serialize via `@MainActor`) and safe for any
    /// future batch-delete scenarios.
    ///
    /// Example: `Notes.md` → `Notes.20260518-093215-A3F2.md`;
    ///          `Documents/` → `Documents.20260518-093215-A3F2/`.
    private static func suffixedWithTimestamp(_ url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: Date())
        let discriminator = String(UUID().uuidString.prefix(4))
        let stamp = "\(timestamp)-\(discriminator)"

        let ext = url.pathExtension
        let withoutExt = url.deletingPathExtension()
        if ext.isEmpty {
            return withoutExt.appendingPathExtension(stamp)
        }
        return
            withoutExt
            .appendingPathExtension(stamp)
            .appendingPathExtension(ext)
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

    /// Recursively enumerates files under `folderURL`, descending into every
    /// non-excluded sub-folder. Excludes:
    /// - any URL in `excludedFolderURLs` (entire subtree is skipped)
    /// - any folder whose last path component begins with `.` or `_`
    /// - any folder named `node_modules` (compiled artefact dir, never user content)
    /// Hidden files are skipped via `.skipsHiddenFiles`.
    ///
    /// Used by the adoption flow to count `.md` and `.json` descendants of a
    /// Vault folder, and by `ContentManager` to surface deeply-nested Pages
    /// under their nearest Collection.
    static func descendantFiles(
        of folderURL: URL,
        excluding excludedFolderURLs: Set<URL> = [],
        where predicate: (URL) -> Bool
    ) throws -> [URL] {
        guard folderExists(at: folderURL) else { return [] }

        let excludedPaths = Set(excludedFolderURLs.map { $0.standardizedFileURL.path })

        guard
            let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDir: Bool = {
                var flag: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &flag)
                return flag.boolValue
            }()

            if isDir {
                let name = url.lastPathComponent
                let isExcludedByName =
                    name.hasPrefix(".") || name.hasPrefix("_") || name == "node_modules"
                let isExcludedByPath = excludedPaths.contains(url.standardizedFileURL.path)
                if isExcludedByName || isExcludedByPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            if predicate(url) {
                results.append(url)
            }
        }
        return results
    }
}

extension String {
    /// Returns the receiver with `prefix` stripped from the front, or `nil`
    /// when `prefix` is not actually a prefix. Used by `Filesystem.moveToTrash`
    /// to derive a path's component relative to the nexus root.
    fileprivate func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
