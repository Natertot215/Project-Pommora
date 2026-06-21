import Foundation

/// One-shot migration that rewrites pre-v0.3.0 name-keyed property values to
/// ID-keyed values across every PageType in a Nexus.
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
/// 2. Bumps `schemaVersion` to `currentTypeSchemaVersion` (2).
/// 3. Builds a name → id map covering every property (existing IDs + minted).
/// 4. Walks every member file under that Type: `.md` files (Pages) in the
///    Type root + every Page Collection sub-folder.
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

    /// Current on-disk **Type-sidecar** schema version (`_pagetype.json`).
    /// Distinct from the index-DB
    /// `PommoraIndex.currentSchemaVersion`. Bumped 1 → 2 for the Relations
    /// redesign: re-encoding a Type sidecar during scan already normalizes
    /// legacy JSON for free (drops a removed `allows_multiple` key, renames
    /// `relation_scope` → `relation_target`, wraps single `$rel` objects into
    /// arrays), so widening the trigger to `< 2` forces a one-time normalizing
    /// re-save of every legacy v1 sidecar. `scan` stamps this; the matching
    /// `PageType.init` default keeps freshly-created Types current so they
    /// never re-migrate.
    static let currentTypeSchemaVersion = 2

    // MARK: - Plan

    struct Plan: Sendable, Equatable {
        var nexusRoot: URL
        /// Page Types that need migration (subset of `pageTypesScanned`).
        var pageTypeMigrations: [TypeMigration]
        /// TOTAL Page Type folders enumerated at the nexus root, including
        /// ones that turned out to need no migration. Surfaced into Report
        /// to preserve the legacy `runIfNeeded` semantic.
        var pageTypesScanned: Int

        var hasAnyMigration: Bool {
            !pageTypeMigrations.isEmpty
        }

        var totalTypes: Int {
            pageTypeMigrations.count
        }

        var totalPropertiesToMint: Int {
            pageTypeMigrations.reduce(0) { $0 + $1.propertiesToMint }
        }

        var totalMemberFileCandidates: Int {
            pageTypeMigrations.reduce(0) { $0 + $1.memberFileCandidates }
        }

        static func empty(at root: URL) -> Plan {
            Plan(
                nexusRoot: root,
                pageTypeMigrations: [],
                pageTypesScanned: 0
            )
        }
    }

    struct TypeMigration: Sendable, Equatable {
        var typeFolderURL: URL
        var typeTitle: String  // folder name; for preview display
        var sidecarURL: URL

        /// Count of properties whose `id` was empty and got freshly minted
        /// during scan. Surfaced in preview as "X new property IDs."
        var propertiesToMint: Int

        /// Count of `.md` files found in the Type folder. An upper bound on
        /// member-file rewrites — apply may skip files whose `properties`
        /// keys are already ID-keyed.
        var memberFileCandidates: Int

        /// Name → ID map for every property in the schema (existing IDs +
        /// newly-minted). Apply uses this to rekey member files.
        var nameToID: [String: String]

        /// Pre-encoded updated Type sidecar JSON (with minted IDs +
        /// `schemaVersion: currentTypeSchemaVersion`). Apply stages this
        /// directly via SchemaTransaction.
        var updatedSchemaJSON: Data
    }

    // MARK: - Report (post-apply)

    struct Report: Sendable, Equatable {
        var pageTypesScanned: Int
        var typesMigrated: Int
        var propertiesMinted: Int
        var memberFilesRewritten: Int
        var failedTypes: [FailedType]

        var didAnyWork: Bool { typesMigrated > 0 }
        var noOp: Bool { !didAnyWork && failedTypes.isEmpty }

        static let empty = Report(
            pageTypesScanned: 0,
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
    /// No disk writes; safe to call repeatedly. The Plan also carries the
    /// `pageTypesScanned` total (including Types that didn't need migration)
    /// so the post-apply Report preserves the legacy "scanned" semantic.
    static func scan(at nexusRoot: URL) -> Plan {
        var pageTypeMigrations: [TypeMigration] = []
        var pageTypesScanned = 0

        for folder in Filesystem.rootTypeFolders(at: nexusRoot) {
            let pageSidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

            if FileManager.default.fileExists(atPath: pageSidecar.path) {
                pageTypesScanned += 1
                if let m = scanPageType(at: folder, sidecarURL: pageSidecar) {
                    pageTypeMigrations.append(m)
                }
            }
        }

        return Plan(
            nexusRoot: nexusRoot,
            pageTypeMigrations: pageTypeMigrations,
            pageTypesScanned: pageTypesScanned
        )
    }

    /// Executes a Plan. Per-Type failures isolated; other Types continue.
    /// Returns the post-apply Report with actual counts (member files
    /// actually rewritten may be less than `memberFileCandidates` if some
    /// already had ID-keyed properties).
    static func apply(_ plan: Plan) -> Report {
        var report = Report.empty
        report.pageTypesScanned = plan.pageTypesScanned

        for migration in plan.pageTypeMigrations {
            applyPageType(migration, into: &report)
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
        mutable.schemaVersion = currentTypeSchemaVersion
        mutable.modifiedAt = Date()

        guard let encoded = try? AtomicJSON.encode(mutable) else { return nil }

        let candidateCount = enumeratePageMembers(in: folder).count
        return TypeMigration(
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

        let validPropIDs = Set(migration.nameToID.values)
        var memberCount = 0
        for pageURL in enumeratePageMembers(in: migration.typeFolderURL) {
            do {
                var pageFile = try PageFile.load(from: pageURL)
                let didRekey = rekey(properties: &pageFile.frontmatter.properties, with: migration.nameToID)
                let didClear = clearOrphanRelationValues(
                    &pageFile.frontmatter.properties, validIDs: validPropIDs)
                if didRekey || didClear {
                    pageFile.frontmatter.modifiedAt = Date()
                    let payload = try AtomicYAMLMarkdown.encode(
                        frontmatter: pageFile.frontmatter, body: pageFile.body,
                        preservingFrom: pageURL, modeledKeys: PageFrontmatter.modeledKeys)
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

    // MARK: - Shared helpers

    /// True iff at least one property has an empty `id` OR the sidecar predates
    /// the current Type-sidecar schema version (`schemaVersion <
    /// currentTypeSchemaVersion`). The version arm catches legacy v1 sidecars
    /// (IDs already present) and re-saves them once to normalize their JSON.
    private static func needsMigration(_ pt: PageType) -> Bool {
        pt.schemaVersion < currentTypeSchemaVersion
            || pt.properties.contains(where: { $0.id.isEmpty })
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

    /// Removes entries from `properties` whose value is a relation shape
    /// (`.relation([...])`) AND whose key is absent from `validIDs` (the migrating
    /// Type's own current property IDs). Used during the migration member-walk to
    /// clear orphaned user-relation values left behind by retired property definitions.
    /// Only operates on the modeled `properties`
    /// dict — root-level tier arrays (`tier1`/`tier2`/`tier3`) are never in this
    /// dict and are therefore never touched.
    /// Returns `true` iff any entry was removed.
    @discardableResult
    private static func clearOrphanRelationValues(
        _ properties: inout [String: PropertyValue], validIDs: Set<String>
    ) -> Bool {
        var removed = false
        for key in properties.keys {
            guard case .relation = properties[key] else { continue }
            if !validIDs.contains(key) {
                properties.removeValue(forKey: key)
                removed = true
            }
        }
        return removed
    }

    private static func enumeratePageMembers(in typeFolder: URL) -> [URL] {
        enumerateMembers(in: typeFolder, withExtensions: ["md"])
    }

    private static func enumerateMembers(
        in folder: URL, withExtensions exts: Set<String>
    ) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if exts.contains(url.pathExtension) {
                results.append(url)
            }
        }
        return results
    }
}
