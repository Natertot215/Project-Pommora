import Foundation

/// One-shot migration that rewrites pre-v0.3.0 name-keyed property values to
/// ID-keyed values across every PageType + ItemType in a Nexus.
///
/// **What it does:**
/// - Walks the nexus root for `_pagetype.json` and `_itemtype.json` sidecars.
/// - For each Type whose schema needs migration (any `PropertyDefinition.id`
///   is empty OR `schemaVersion < 1`):
///   1. Mints `prop_<ulid>` IDs for every property whose `id` is empty.
///   2. Bumps `schemaVersion` to `1`.
///   3. Builds a name → id map.
///   4. Walks every member file under that Type:
///      - PageType: `.md` files (Pages) in the Type root + every Page
///        Collection sub-folder (carrying `_pagecollection.json`).
///      - ItemType: `.json` files (Items) similarly. Excludes sidecar files
///        (`_itemcollection.json`).
///   5. Per member, rekeys the `properties` block from `name` to `id`
///      (entries whose name isn't in the map are preserved as-is —
///      orphan-property cleanup belongs to validation, not migration).
///   6. Stages the updated Type sidecar + every rewritten member into a
///      single SchemaTransaction; commits atomically. Per-Type failures are
///      isolated; other Types continue.
///
/// **Agenda schemas (`_taskconfig.json` / `_eventconfig.json`) are NOT
/// migrated here** — their schemas use a separate `Property` struct without
/// an `id` field; Phase G's Status-seed work handles their ID-truth story
/// when it injects `PropertyDefinition` `_status` entries.
///
/// **Idempotent:** re-runs on already-migrated nexuses skip every Type and
/// report zero work.
enum PropertyIDMigration {

    struct Report: Sendable, Equatable {
        var pageTypesScanned: Int
        var itemTypesScanned: Int
        var typesMigrated: Int
        var propertiesMinted: Int
        var memberFilesRewritten: Int
        var failedTypes: [FailedType]

        var didAnyWork: Bool { typesMigrated > 0 }
        var noOp: Bool { !didAnyWork && failedTypes.isEmpty }

        static let empty = Report(
            pageTypesScanned: 0, itemTypesScanned: 0,
            typesMigrated: 0, propertiesMinted: 0,
            memberFilesRewritten: 0, failedTypes: []
        )
    }

    struct FailedType: Sendable, Equatable {
        var typeFolderURL: URL
        var message: String
    }

    /// Top-level entry point. Always returns a report; never throws.
    /// Per-Type errors are isolated in `report.failedTypes`.
    static func runIfNeeded(at nexusRoot: URL) -> Report {
        var report = Report.empty
        let roots = enumerateRootTypeFolders(at: nexusRoot)

        for folder in roots {
            let pageSidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            let itemSidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)

            if FileManager.default.fileExists(atPath: pageSidecar.path) {
                report.pageTypesScanned += 1
                migratePageType(at: folder, sidecarURL: pageSidecar, into: &report)
            } else if FileManager.default.fileExists(atPath: itemSidecar.path) {
                report.itemTypesScanned += 1
                migrateItemType(at: folder, sidecarURL: itemSidecar, into: &report)
            }
        }
        return report
    }

    // MARK: - PageType

    private static func migratePageType(at folder: URL, sidecarURL: URL, into report: inout Report) {
        var pageType: PageType
        do {
            pageType = try PageType.load(from: sidecarURL)
        } catch {
            report.failedTypes.append(
                FailedType(typeFolderURL: folder, message: "decode failed: \(error)"))
            return
        }

        guard needsMigration(pageType) else { return }

        let mintResult = mintMissingIDs(in: &pageType.properties)
        pageType.schemaVersion = 1
        pageType.modifiedAt = Date()

        let txn = SchemaTransaction()
        do {
            try txn.stage(pageType, to: sidecarURL)
        } catch {
            report.failedTypes.append(
                FailedType(typeFolderURL: folder, message: "encode failed: \(error)"))
            return
        }

        var memberCount = 0
        let pageURLs = enumeratePageMembers(in: folder)
        for pageURL in pageURLs {
            do {
                var pageFile = try PageFile.load(from: pageURL)
                if rekey(properties: &pageFile.frontmatter.properties, with: mintResult.nameToID) {
                    pageFile.frontmatter.modifiedAt = Date()
                    let payload = try AtomicYAMLMarkdown.encode(
                        frontmatter: pageFile.frontmatter, body: pageFile.body)
                    txn.stage(payload: payload, to: pageURL)
                    memberCount += 1
                }
            } catch {
                // Single-file decode failure doesn't sink the whole Type; log via
                // failedTypes but keep going.
                report.failedTypes.append(
                    FailedType(
                        typeFolderURL: pageURL,
                        message: "page rewrite skipped: \(error)"))
            }
        }

        do {
            try txn.commit()
            report.typesMigrated += 1
            report.propertiesMinted += mintResult.minted
            report.memberFilesRewritten += memberCount
        } catch {
            report.failedTypes.append(
                FailedType(typeFolderURL: folder, message: "commit failed: \(error)"))
        }
    }

    // MARK: - ItemType

    private static func migrateItemType(at folder: URL, sidecarURL: URL, into report: inout Report) {
        var itemType: ItemType
        do {
            itemType = try ItemType.load(from: sidecarURL)
        } catch {
            report.failedTypes.append(
                FailedType(typeFolderURL: folder, message: "decode failed: \(error)"))
            return
        }

        guard needsMigration(itemType) else { return }

        let mintResult = mintMissingIDs(in: &itemType.properties)
        itemType.schemaVersion = 1
        itemType.modifiedAt = Date()

        let txn = SchemaTransaction()
        do {
            try txn.stage(itemType, to: sidecarURL)
        } catch {
            report.failedTypes.append(
                FailedType(typeFolderURL: folder, message: "encode failed: \(error)"))
            return
        }

        var memberCount = 0
        let itemURLs = enumerateItemMembers(in: folder)
        for itemURL in itemURLs {
            do {
                var item = try AtomicJSON.decode(Item.self, from: itemURL)
                if rekey(properties: &item.properties, with: mintResult.nameToID) {
                    item.modifiedAt = Date()
                    try txn.stage(item, to: itemURL)
                    memberCount += 1
                }
            } catch {
                report.failedTypes.append(
                    FailedType(
                        typeFolderURL: itemURL,
                        message: "item rewrite skipped: \(error)"))
            }
        }

        do {
            try txn.commit()
            report.typesMigrated += 1
            report.propertiesMinted += mintResult.minted
            report.memberFilesRewritten += memberCount
        } catch {
            report.failedTypes.append(
                FailedType(typeFolderURL: folder, message: "commit failed: \(error)"))
        }
    }

    // MARK: - Helpers

    /// True iff at least one property has an empty `id` OR the schema is
    /// pre-v0.3.0 (`schemaVersion < 1`).
    private static func needsMigration(_ pt: PageType) -> Bool {
        pt.schemaVersion < 1 || pt.properties.contains(where: { $0.id.isEmpty })
    }

    private static func needsMigration(_ it: ItemType) -> Bool {
        it.schemaVersion < 1 || it.properties.contains(where: { $0.id.isEmpty })
    }

    private struct MintResult {
        var nameToID: [String: String]
        var minted: Int
    }

    /// Walks `properties` in place; for any with empty `id`, mints
    /// `prop_<ulid>`. Returns the name → final-id map (covers every
    /// property, including ones that already had IDs — so the member-file
    /// rekey pass can look them up by display name).
    private static func mintMissingIDs(in properties: inout [PropertyDefinition]) -> MintResult {
        var map: [String: String] = [:]
        var minted = 0
        for idx in properties.indices {
            if properties[idx].id.isEmpty {
                properties[idx].id = ReservedPropertyID.mintUserPropertyID()
                minted += 1
            }
            map[properties[idx].name] = properties[idx].id
        }
        return MintResult(nameToID: map, minted: minted)
    }

    /// Rekeys every entry in `properties` whose key matches a name in `map`.
    /// Entries whose key is already an ID (`prop_*` or `_*`) or whose key
    /// isn't in the map are left untouched. Returns `true` iff any rekey
    /// happened (so the caller knows whether to write back).
    private static func rekey(
        properties: inout [String: PropertyValue], with map: [String: String]
    ) -> Bool {
        var changed = false
        var newDict: [String: PropertyValue] = [:]
        for (key, value) in properties {
            if key.hasPrefix("prop_") || key.hasPrefix("_") {
                // Already ID-keyed — preserve as-is.
                newDict[key] = value
            } else if let id = map[key] {
                newDict[id] = value
                changed = true
            } else {
                // Orphan property — keep under the original key. Validation
                // can surface this separately; we don't drop user data here.
                newDict[key] = value
            }
        }
        if changed {
            properties = newDict
        }
        return changed
    }

    /// Top-level scan of the nexus root for adoption-eligible folders (skips
    /// `.`-prefixed + `_`-prefixed siblings — matches NexusAdopter's
    /// exclusion rule).
    private static func enumerateRootTypeFolders(at nexusRoot: URL) -> [URL] {
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

    /// Recursively walks a PageType folder for `.md` files. Skips sidecar
    /// files (any name starting with `_`).
    private static func enumeratePageMembers(in typeFolder: URL) -> [URL] {
        enumerateMembers(in: typeFolder, withExtension: "md")
    }

    /// Recursively walks an ItemType folder for `.json` files. Skips
    /// sidecar files (`_itemtype.json`, `_itemcollection.json`).
    private static func enumerateItemMembers(in typeFolder: URL) -> [URL] {
        enumerateMembers(in: typeFolder, withExtension: "json").filter {
            !$0.lastPathComponent.hasPrefix("_")
        }
    }

    private static func enumerateMembers(in folder: URL, withExtension ext: String) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == ext {
                results.append(url)
            }
        }
        return results
    }
}
