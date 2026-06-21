import Foundation

/// Errors thrown by `Filesystem` primitives.
enum FilesystemError: LocalizedError {
    /// Raised by the relocation core (`moveToTrash`) when the source URL
    /// doesn't sit under the nexus root — we refuse to relocate paths outside
    /// the user's nexus.
    case sourceNotInNexus(source: URL, nexus: URL)
    /// Raised by `renameFile` when the destination already exists and is a
    /// *different* file from the source. Defense-in-depth against silent
    /// data loss: a rename that would clobber a sibling's file is refused at
    /// the primitive even if a caller skipped name-collision validation. A
    /// same-path rename (source == destination) is allowed through as a no-op.
    case destinationExists(destination: URL)

    var errorDescription: String? {
        switch self {
        case .sourceNotInNexus(let source, let nexus):
            return "Cannot relocate: \(source.path) is not inside nexus root \(nexus.path)."
        case .destinationExists(let destination):
            return "An entry named \"\(destination.lastPathComponent)\" already exists here."
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

    /// Throws `error` when a file already exists at `url`. The one shared shape
    /// of the per-side "don't clobber a different entity's file on create" guard
    /// (Page / Agenda all route through this). Each side passes its own
    /// `duplicateTitle` error so its toast wording is preserved (DRY hard rule).
    /// Create-only: a freshly-minted entity owns a new id, so ANY file already at
    /// the target path belongs to a different entity — no canonical-identity
    /// escape hatch is needed here (that lives in `renameFile`, where a self-recase
    /// is legitimate).
    static func guardNoFile(at url: URL, else error: @autoclosure () -> any Error) throws {
        if fileExists(at: url) { throw error() }
    }

    /// Renames/moves a file. Refuses to overwrite a *different* existing file at
    /// `newURL` (defense-in-depth against the duplicate-title overwrite data
    /// loss — see `NameCollisionValidator`). A move whose destination resolves to
    /// the SAME underlying file as the source is allowed through, so renaming an
    /// entity to its own current title — including a case-only recase on a
    /// case-insensitive volume (APFS), e.g. `notes` → `Notes` — never errors:
    /// `moveItem` recases in place. We only throw when `newURL` names a
    /// *genuinely different* file.
    static func renameFile(from oldURL: URL, to newURL: URL) throws {
        if oldURL.standardizedFileURL == newURL.standardizedFileURL { return }
        if fileExists(at: newURL), !isSameUnderlyingFile(oldURL, newURL) {
            throw FilesystemError.destinationExists(destination: newURL)
        }
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    /// True when both URLs resolve to the SAME underlying file. On a
    /// case-insensitive volume `notes` and `Notes` are one file; their
    /// `standardizedFileURL` strings differ (no case fold) but their filesystem
    /// identity is identical — this is the self-recase case `renameFile` must
    /// allow. Compares the volume-scoped `fileResourceIdentifierKey` (the
    /// authoritative same-file token); falls back to comparing resolved canonical
    /// (symlink-flattened, case-normalized) paths when the key is unavailable.
    private static func isSameUnderlyingFile(_ a: URL, _ b: URL) -> Bool {
        if let idA = (try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier,
            let idB = (try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
                .fileResourceIdentifier
        {
            return idA.isEqual(idB)
        }
        // Fallback: resolveSymlinksInPath canonicalizes (and case-normalizes on a
        // case-insensitive volume) so a self-recase compares equal here too.
        return a.resolvingSymlinksInPath().standardizedFileURL.path
            == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Two-step folder+metadata atomicity

    /// Creates `folderURL`, then writes `metadata` (a `Codable` value) to `metadataURL`.
    /// If the metadata write fails, the folder is deleted before the error propagates.
    ///
    /// Used by Topic + PageType creation flows (Topic = folder +
    /// `_topic.json`; PageType = folder + `_pagetype.json`).
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

    // MARK: - Relocation (trash)

    /// Shared core behind `moveToTrash`: moves `source`
    /// into `destDir`, preserving its relative path under `nexusRoot`. Refuses
    /// to relocate a source outside the nexus (out-of-nexus guard), standardizes
    /// the source URL, recreates intermediate directories under `destDir`, and
    /// de-collides via `suffixedWithTimestamp` when an entry already occupies the
    /// proposed destination.
    ///
    /// Returns the URL the entry was moved to.
    private static func relocate(_ source: URL, into destDir: URL, nexusRoot: URL) throws -> URL {
        let standardizedSource = source.standardizedFileURL

        // Compute the relative path under nexus root (preserves the user's folder
        // structure inside `destDir`). The guard rejects out-of-nexus sources.
        guard
            let relativePath = standardizedSource.path.removingPrefix(
                nexusRoot.standardizedFileURL.path + "/"
            )
        else {
            throw FilesystemError.sourceNotInNexus(source: source, nexus: nexusRoot)
        }
        let proposedDest = destDir.appendingPathComponent(relativePath)

        let proposedParent = proposedDest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: proposedParent, withIntermediateDirectories: true)

        // Collision resolution via timestamp suffix.
        let finalDest =
            FileManager.default.fileExists(atPath: proposedDest.path)
            ? suffixedWithTimestamp(proposedDest)
            : proposedDest

        try FileManager.default.moveItem(at: standardizedSource, to: finalDest)
        return finalDest
    }

    /// Move a file or folder to the nexus's `.trash//` directory, preserving
    /// its relative path under the nexus root. If a previously-deleted entry
    /// already exists at the same trash path, the new entry is suffixed with
    /// a timestamp (e.g. `Notes.20260518-093215.md`) to avoid collision.
    ///
    /// Returns the URL the entry was moved to (useful for tests + future
    /// "Recover deleted" UI).
    @discardableResult
    static func moveToTrash(_ source: URL, in nexus: Nexus) throws -> URL {
        try relocate(source, into: NexusPaths.trashDir(in: nexus), nexusRoot: nexus.rootURL)
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

    /// Returns immediate child folders (not files). Folders matching `folderFilter`
    /// are excluded from the result.
    static func childFolders(of folderURL: URL, folderFilter: FolderFilter = .empty) throws -> [URL] {
        try children(of: folderURL) { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        .filter { !folderFilter.isExcluded($0) }
    }

    /// Top-level scan of the nexus root for adoption-eligible Type folders:
    /// immediate child directories, skipping `.`-prefixed + `_`-prefixed
    /// siblings. Matches `NexusAdopter`'s exclusion rule and is the single
    /// source for the launch-time migration (`PropertyIDMigration`).
    /// Returns `[]` when the root can't be read.
    static func rootTypeFolders(at nexusRoot: URL) -> [URL] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: nexusRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        return entries.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
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
        folderFilter: FolderFilter = .empty,
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
                if isExcludedByName || isExcludedByPath || folderFilter.isExcluded(url) {
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
    /// when `prefix` is not actually a prefix. Used by `Filesystem.relocate`
    /// (the `moveToTrash` core) to derive a path's component relative to the
    /// nexus root.
    fileprivate func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
