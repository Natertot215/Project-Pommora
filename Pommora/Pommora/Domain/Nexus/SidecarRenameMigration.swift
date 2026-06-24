import Foundation

/// One-shot, idempotent Phase-3 migration that unifies the Pages sidecar
/// filenames and canonicalizes every parent-ref key.
///
/// Pre-Phase-3 the Pages side used three sidecar names by tier — top Collection
/// `_pagetype.json`, depth-1 Set `_pagecollection.json`, deeper Sub-Set
/// `_pageset.json` — and parent refs were keyed `vault_id` / `type_id` /
/// `collection_id` across eras. This rewrites every Pages tree to the unified
/// scheme: the top Collection is `_pagecollection.json`; every Set at any depth
/// is `_pageset.json` with its parent keyed `parent_id`.
///
/// **Per-Collection, descendants-first.** A top-down pass would collide the two
/// legacy meanings of `_pagecollection.json` (a depth-1 Set vs the freshly
/// renamed top Collection); renaming the deepest sidecars first avoids it. A
/// folder's role is decided by its position (root vs nested), never by the
/// sidecar's current name.
///
/// **Idempotent.** A fully migrated nexus has no legacy filenames and no legacy
/// parent keys, so the scan finds nothing and the whole call is a no-op.
///
/// **Transactional backup.** Every sidecar the migration will touch is copied
/// into `<nexus>/.nexus/migration-backup-<stamp>/` (relative path preserved)
/// before any rename. On success the backup is deleted; if the migration
/// throws, the backup is retained for recovery and the partially migrated tree
/// stays readable — a re-run completes it.
enum SidecarRenameMigration {

    struct Report: Equatable, Sendable {
        var collectionsRenamed = 0  // _pagetype.json → _pagecollection.json
        var setsRenamed = 0  // _pagecollection.json → _pageset.json
        var keysRewritten = 0  // legacy parent key → parent_id, no rename
        var noOp: Bool { collectionsRenamed == 0 && setsRenamed == 0 && keysRewritten == 0 }
    }

    private static let legacyParentKeys = ["vault_id", "type_id", "collection_id"]

    @discardableResult
    static func migrateIfNeeded(at nexusRoot: URL) throws -> Report {
        let roots = Filesystem.rootTypeFolders(at: nexusRoot).filter(isPageCollectionRoot)

        var affected: [URL] = []
        for root in roots { collectAffected(in: root, depth: 0, into: &affected) }
        guard !affected.isEmpty else { return Report() }

        let backupDir =
            nexusRoot
            .appendingPathComponent(".nexus", isDirectory: true)
            .appendingPathComponent("migration-backup-\(backupStamp())", isDirectory: true)
        try backUp(affected, nexusRoot: nexusRoot, to: backupDir)

        var report = Report()
        for root in roots { try migrateCollection(root, into: &report) }

        try? FileManager.default.removeItem(at: backupDir)  // success → drop the temp
        return report
    }

    // MARK: - Scan

    private static func isPageCollectionRoot(_ folder: URL) -> Bool {
        sidecarExists(folder, NexusPaths.legacyPageTypeSidecarFilename)
            || sidecarExists(folder, NexusPaths.pageCollectionSidecarFilename)
    }

    private static func collectAffected(in folder: URL, depth: Int, into out: inout [URL]) {
        if depth == 0 {
            let legacy = folder.appendingPathComponent(NexusPaths.legacyPageTypeSidecarFilename)
            if FileManager.default.fileExists(atPath: legacy.path) { out.append(legacy) }
        } else {
            let legacyColl = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            let set = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            if FileManager.default.fileExists(atPath: legacyColl.path) {
                out.append(legacyColl)
            } else if FileManager.default.fileExists(atPath: set.path), hasLegacyParentKey(set) {
                out.append(set)
            }
        }
        for child in childFolders(folder) {
            collectAffected(in: child, depth: depth + 1, into: &out)
        }
    }

    // MARK: - Migrate

    private static func migrateCollection(_ root: URL, into report: inout Report) throws {
        for child in childFolders(root) { try migrateSetFolder(child, into: &report) }  // descendants first

        let legacyTop = root.appendingPathComponent(NexusPaths.legacyPageTypeSidecarFilename)
        guard FileManager.default.fileExists(atPath: legacyTop.path) else { return }
        let target = root.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let collection = try PageCollection.load(from: legacyTop)
        try collection.save(to: target)
        try FileManager.default.removeItem(at: legacyTop)
        report.collectionsRenamed += 1
    }

    private static func migrateSetFolder(_ folder: URL, into report: inout Report) throws {
        for child in childFolders(folder) { try migrateSetFolder(child, into: &report) }  // bottom-up

        let setURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
        let legacyColl = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        if FileManager.default.fileExists(atPath: legacyColl.path) {
            let set = try PageSet.load(from: legacyColl)
            try set.save(to: setURL)
            try FileManager.default.removeItem(at: legacyColl)
            report.setsRenamed += 1
        } else if FileManager.default.fileExists(atPath: setURL.path), hasLegacyParentKey(setURL) {
            let set = try PageSet.load(from: setURL)
            try set.save(to: setURL)
            report.keysRewritten += 1
        }
    }

    // MARK: - Helpers

    /// Child folders, defensively skipping dot/underscore-prefixed dirs so the
    /// walk never descends into `.nexus`, sidecar-adjacent hidden dirs, or the
    /// migration backup itself.
    private static func childFolders(_ folder: URL) -> [URL] {
        ((try? Filesystem.childFolders(of: folder)) ?? []).filter {
            let n = $0.lastPathComponent
            return !n.hasPrefix(".") && !n.hasPrefix("_")
        }
    }

    private static func sidecarExists(_ folder: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    private static func hasLegacyParentKey(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return legacyParentKeys.contains { obj[$0] != nil }
    }

    private static func backUp(_ urls: [URL], nexusRoot: URL, to backupDir: URL) throws {
        let fm = FileManager.default
        let rootPath = nexusRoot.standardizedFileURL.path
        for url in urls {
            let rel = url.standardizedFileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            let dest = backupDir.appendingPathComponent(rel)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: dest)
        }
    }

    private static func backupStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
