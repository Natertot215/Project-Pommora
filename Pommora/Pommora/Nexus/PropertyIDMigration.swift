import Foundation

/// One-shot migration that rewrites pre-v0.3.0 name-keyed property values to
/// ID-keyed values across every PageType + ItemType in a Nexus.
///
/// Two-phase API:
///   - `scan(at:) -> Plan` — pure: walks the nexus, mints `prop_<ulid>` IDs
///     into a pre-encoded Plan, returns counts for preview UI. **No disk
///     writes.**
///   - `apply(_:) -> Report` — executes the Plan: writes the updated schema
///     sidecars + walks member files + rekeys their `properties` blocks via
///     the Plan's per-Type `name → id` map. Per-Type atomic via
///     SchemaTransaction; per-Type failures isolated in `report.failedTypes`.
///
/// `runIfNeeded(at:)` is the legacy entry — equivalent to
/// `apply(scan(at:))`. Use it when no preview UI is needed (tests, headless
/// flows); `NexusManager.runAdoptionIfNeeded` uses scan + apply explicitly so
/// `AdoptionPreviewView` can show counts before commit (Phase C.5).
///
/// **What it does (per migrating Type):**
/// 1. Mints `prop_<ulid>` IDs for every property whose `id` is empty.
/// 2. Bumps `schemaVersion` to `1`.
/// 3. Builds a name → id map covering every property (existing IDs + minted).
/// 4. Walks every member file under that Type:
///    - PageType: `.md` files (Pages) in the Type root + every Page
///      Collection sub-folder.
///    - ItemType: `.json` files (Items) similarly. Excludes sidecar files
///      (`_itemcollection.json`).
/// 5. Per member, rekeys the `properties` block from name to id (entries
///    whose name isn't in the map are preserved — orphan-property cleanup
///    belongs to validation, not migration).
/// 6. Stages the updated Type sidecar + every rewritten member into a single
///    SchemaTransaction; commits atomically.
///
/// **Agenda schemas (`_taskconfig.json` / `_eventconfig.json`) are NOT
/// migrated here** — their schemas use a separate `Property` struct without
/// an `id` field; Phase G's Status-seed work handles their ID-truth story.
///
/// **Idempotent:** scan returns `Plan.empty` for already-migrated nexuses.
enum PropertyIDMigration {

    // MARK: - Plan

    struct Plan: Sendable, Equatable {
        var nexusRoot: URL
        /// Page Types that need migration (subset of `pageTypesScanned`).
        var pageTypeMigrations: [TypeMigration]
        /// Item Types that need migration (subset of `itemTypesScanned`).
        var itemTypeMigrations: [TypeMigration]
        /// TOTAL Page Type folders enumerated at the nexus root, including
        /// ones that turned out to need no migration. Surfaced into Report
        /// to preserve the legacy `runIfNeeded` semantic.
        var pageTypesScanned: Int
        /// TOTAL Item Type folders enumerated at the nexus root, including
        /// ones that turned out to need no migration.
        var itemTypesScanned: Int

        var hasAnyMigration: Bool {
            !pageTypeMigrations.isEmpty || !itemTypeMigrations.isEmpty
        }

        var totalTypes: Int {
            pageTypeMigrations.count + itemTypeMigrations.count
        }

        var totalPropertiesToMint: Int {
            pageTypeMigrations.reduce(0) { $0 + $1.propertiesToMint }
                + itemTypeMigrations.reduce(0) { $0 + $1.propertiesToMint }
        }

        var totalMemberFileCandidates: Int {
            pageTypeMigrations.reduce(0) { $0 + $1.memberFileCandidates }
                + itemTypeMigrations.reduce(0) { $0 + $1.memberFileCandidates }
        }

        static func empty(at root: URL) -> Plan {
            Plan(
                nexusRoot: root,
                pageTypeMigrations: [], itemTypeMigrations: [],
                pageTypesScanned: 0, itemTypesScanned: 0
            )
        }
    }

    struct TypeMigration: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case pageType
            case itemType
        }

        var kind: Kind
        var typeFolderURL: URL
        var typeTitle: String  // folder name; for preview display
        var sidecarURL: URL

        /// Count of properties whose `id` was empty and got freshly minted
        /// during scan. Surfaced in preview as "X new property IDs."
        var propertiesToMint: Int

        /// Count of `.md` (PageType) or `.json` (ItemType) files found in the
        /// Type folder. An upper bound on member-file rewrites — apply may
        /// skip files whose `properties` keys are already ID-keyed.
        var memberFileCandidates: Int

        /// Name → ID map for every property in the schema (existing IDs +
        /// newly-minted). Apply uses this to rekey member files.
        var nameToID: [String: String]

        /// Pre-encoded updated Type sidecar JSON (with minted IDs +
        /// `schemaVersion: 1`). Apply stages this directly via
        /// SchemaTransaction.
        var updatedSchemaJSON: Data
    }

    // MARK: - Report (post-apply)

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

    // MARK: - Entry points

    /// Pure scan — computes a Plan covering every Type that needs migration.
    /// No disk writes; safe to call repeatedly. The Plan also carries
    /// `pageTypesScanned` / `itemTypesScanned` totals (including Types that
    /// didn't need migration) so the post-apply Report preserves the legacy
    /// "scanned" semantic.
    static func scan(at nexusRoot: URL) -> Plan {
        var pageTypeMigrations: [TypeMigration] = []
        var itemTypeMigrations: [TypeMigration] = []
        var pageTypesScanned = 0
        var itemTypesScanned = 0

        for folder in enumerateRootTypeFolders(at: nexusRoot) {
            let pageSidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            let itemSidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)

            if FileManager.default.fileExists(atPath: pageSidecar.path) {
                pageTypesScanned += 1
                if let m = scanPageType(at: folder, sidecarURL: pageSidecar) {
                    pageTypeMigrations.append(m)
                }
            } else if FileManager.default.fileExists(atPath: itemSidecar.path) {
                itemTypesScanned += 1
                if let m = scanItemType(at: folder, sidecarURL: itemSidecar) {
                    itemTypeMigrations.append(m)
                }
            }
        }

        return Plan(
            nexusRoot: nexusRoot,
            pageTypeMigrations: pageTypeMigrations,
            itemTypeMigrations: itemTypeMigrations,
            pageTypesScanned: pageTypesScanned,
            itemTypesScanned: itemTypesScanned
        )
    }

    /// Executes a Plan. Per-Type failures isolated; other Types continue.
    /// Returns the post-apply Report with actual counts (member files
    /// actually rewritten may be less than `memberFileCandidates` if some
    /// already had ID-keyed properties).
    static func apply(_ plan: Plan) -> Report {
        var report = Report.empty
        report.pageTypesScanned = plan.pageTypesScanned
        report.itemTypesScanned = plan.itemTypesScanned

        for migration in plan.pageTypeMigrations {
            applyPageType(migration, into: &report)
        }
        for migration in plan.itemTypeMigrations {
            applyItemType(migration, into: &report)
        }
        return report
    }

    /// Legacy single-call entry. Equivalent to `apply(scan(at:))`. Kept for
    /// tests + headless flows that don't need preview UI.
    static func runIfNeeded(at nexusRoot: URL) -> Report {
        apply(scan(at: nexusRoot))
    }

    // MARK: - Scan helpers

    private static func scanPageType(at folder: URL, sidecarURL: URL) -> TypeMigration? {
        guard let pageType = try? PageType.load(from: sidecarURL),
            needsMigration(pageType)
        else { return nil }

        var mutable = pageType
        let mintResult = mintMissingIDs(in: &mutable.properties)
        mutable.schemaVersion = 1
        mutable.modifiedAt = Date()

        guard let encoded = try? AtomicJSON.encode(mutable) else { return nil }

        let candidateCount = enumeratePageMembers(in: folder).count
        return TypeMigration(
            kind: .pageType,
            typeFolderURL: folder,
            typeTitle: folder.lastPathComponent,
            sidecarURL: sidecarURL,
            propertiesToMint: mintResult.minted,
            memberFileCandidates: candidateCount,
            nameToID: mintResult.nameToID,
            updatedSchemaJSON: encoded
        )
    }

    private static func scanItemType(at folder: URL, sidecarURL: URL) -> TypeMigration? {
        guard let itemType = try? ItemType.load(from: sidecarURL),
            needsMigration(itemType)
        else { return nil }

        var mutable = itemType
        let mintResult = mintMissingIDs(in: &mutable.properties)
        mutable.schemaVersion = 1
        mutable.modifiedAt = Date()

        guard let encoded = try? AtomicJSON.encode(mutable) else { return nil }

        let candidateCount = enumerateItemMembers(in: folder).count
        return TypeMigration(
            kind: .itemType,
            typeFolderURL: folder,
            typeTitle: folder.lastPathComponent,
            sidecarURL: sidecarURL,
            propertiesToMint: mintResult.minted,
            memberFileCandidates: candidateCount,
            nameToID: mintResult.nameToID,
            updatedSchemaJSON: encoded
        )
    }

    // MARK: - Apply helpers

    private static func applyPageType(_ migration: TypeMigration, into report: inout Report) {
        let txn = SchemaTransaction()
        txn.stage(payload: migration.updatedSchemaJSON, to: migration.sidecarURL)

        var memberCount = 0
        for pageURL in enumeratePageMembers(in: migration.typeFolderURL) {
            do {
                var pageFile = try PageFile.load(from: pageURL)
                if rekey(properties: &pageFile.frontmatter.properties, with: migration.nameToID) {
                    pageFile.frontmatter.modifiedAt = Date()
                    let payload = try AtomicYAMLMarkdown.encode(
                        frontmatter: pageFile.frontmatter, body: pageFile.body)
                    txn.stage(payload: payload, to: pageURL)
                    memberCount += 1
                }
            } catch {
                report.failedTypes.append(
                    FailedType(
                        typeFolderURL: pageURL,
                        message: "page rewrite skipped: \(error)"))
            }
        }

        do {
            try txn.commit()
            report.typesMigrated += 1
            report.propertiesMinted += migration.propertiesToMint
            report.memberFilesRewritten += memberCount
        } catch {
            report.failedTypes.append(
                FailedType(
                    typeFolderURL: migration.typeFolderURL,
                    message: "commit failed: \(error)"))
        }
    }

    private static func applyItemType(_ migration: TypeMigration, into report: inout Report) {
        let txn = SchemaTransaction()
        txn.stage(payload: migration.updatedSchemaJSON, to: migration.sidecarURL)

        var memberCount = 0
        for itemURL in enumerateItemMembers(in: migration.typeFolderURL) {
            do {
                var item = try AtomicJSON.decode(Item.self, from: itemURL)
                if rekey(properties: &item.properties, with: migration.nameToID) {
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
            report.propertiesMinted += migration.propertiesToMint
            report.memberFilesRewritten += memberCount
        } catch {
            report.failedTypes.append(
                FailedType(
                    typeFolderURL: migration.typeFolderURL,
                    message: "commit failed: \(error)"))
        }
    }

    // MARK: - Shared helpers

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
                newDict[key] = value
            } else if let id = map[key] {
                newDict[id] = value
                changed = true
            } else {
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

    private static func enumeratePageMembers(in typeFolder: URL) -> [URL] {
        enumerateMembers(in: typeFolder, withExtension: "md")
    }

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
