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
/// 2. Bumps `schemaVersion` to `currentTypeSchemaVersion` (2).
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

    /// Current on-disk **Type-sidecar** schema version (`_pagetype.json` /
    /// `_itemtype.json`). Distinct from the index-DB
    /// `PommoraIndex.currentSchemaVersion`. Bumped 1 → 2 for the Relations
    /// redesign: re-encoding a Type sidecar during scan already normalizes
    /// legacy JSON for free (drops a removed `allows_multiple` key, renames
    /// `relation_scope` → `relation_target`, wraps single `$rel` objects into
    /// arrays), so widening the trigger to `< 2` forces a one-time normalizing
    /// re-save of every legacy v1 sidecar. `scan` stamps this; the matching
    /// `PageType.init` / `ItemType.init` defaults keep freshly-created Types
    /// current so they never re-migrate.
    static let currentTypeSchemaVersion = 2

    // MARK: - Collection-parent map

    /// Nexus-wide lookup from a Collection's ULID to its parent Type's ULID.
    /// Built once at the top of `scan(at:)` by walking every root Type folder
    /// and its immediate sub-folders; used to rewrite legacy
    /// `.pageCollection` / `.itemCollection` relation targets onto the parent
    /// Type (Collections aren't valid relation targets post-Relations-redesign).
    struct CollectionParentMap: Sendable, Equatable {
        var pageCollections: [String: String]  // collectionID → parent PageType ID
        var itemCollections: [String: String]  // collectionID → parent ItemType ID

        static let empty = CollectionParentMap(pageCollections: [:], itemCollections: [:])
    }

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

        /// Every per-property MigrationEvent across all migrating Types, flattened
        /// for the adoption preview sheet. Populated by scan's relation transforms
        /// (Collection→Type rewrites + context_tier drops).
        var allEvents: [MigrationEvent] {
            pageTypeMigrations.flatMap(\.events) + itemTypeMigrations.flatMap(\.events)
        }

        /// True iff the migration contains a LOSSY change the user must explicitly
        /// acknowledge before commit (today: dropping a context-tier-targeted
        /// relation property). Lossless normalizations do not require consent and
        /// apply silently. Single source of truth for both the launch-gate
        /// (NexusManager) and the Adopt-button gate (AdoptionPreviewView).
        var requiresAcknowledgment: Bool {
            allEvents.contains { event in
                if case .contextTierDropped = event { return true }
                return false
            }
        }

        /// Per-tier counts of context-tier-drop events, for preview display.
        /// Key = tier (1/2/3), value = number of relation properties dropped.
        var contextTierDropCountsByTier: [Int: Int] {
            var counts: [Int: Int] = [:]
            for case .contextTierDropped(_, let tier, _) in allEvents {
                counts[tier, default: 0] += 1
            }
            return counts
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
        /// `schemaVersion: currentTypeSchemaVersion`). Apply stages this
        /// directly via SchemaTransaction.
        var updatedSchemaJSON: Data

        /// Per-property MigrationEvents surfaced in the adoption preview
        /// (Collection→Type rewrites + context_tier drops). Empty for a Type
        /// that needed only a plain ID-mint / version-bump pass.
        var events: [MigrationEvent] = []
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

        // Build the Collection-parent map once up front so both scan helpers
        // can rewrite legacy `.pageCollection` / `.itemCollection` targets onto
        // their parent Type.
        let parentMap = buildCollectionParentMap(at: nexusRoot)

        for folder in enumerateRootTypeFolders(at: nexusRoot) {
            let pageSidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            let itemSidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)

            if FileManager.default.fileExists(atPath: pageSidecar.path) {
                pageTypesScanned += 1
                if let m = scanPageType(at: folder, sidecarURL: pageSidecar, parentMap: parentMap) {
                    pageTypeMigrations.append(m)
                }
            } else if FileManager.default.fileExists(atPath: itemSidecar.path) {
                itemTypesScanned += 1
                if let m = scanItemType(at: folder, sidecarURL: itemSidecar, parentMap: parentMap) {
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

    private static func scanPageType(
        at folder: URL, sidecarURL: URL, parentMap: CollectionParentMap
    ) -> TypeMigration? {
        guard let pageType = try? PageType.load(from: sidecarURL),
            needsMigration(pageType)
        else { return nil }

        var mutable = pageType
        let mintResult = mintMissingIDs(in: &mutable.properties)
        // Relation transforms ride along on the v1→v2 pass: rewrite legacy
        // Collection targets onto their parent Type, then drop context_tier
        // declarations. Both record MigrationEvents for the preview sheet.
        let events = applyRelationTransforms(
            to: &mutable.properties, typeID: mutable.id, parentMap: parentMap)
        mutable.schemaVersion = currentTypeSchemaVersion
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
            updatedSchemaJSON: encoded,
            events: events
        )
    }

    private static func scanItemType(
        at folder: URL, sidecarURL: URL, parentMap: CollectionParentMap
    ) -> TypeMigration? {
        guard let itemType = try? ItemType.load(from: sidecarURL),
            needsMigration(itemType)
        else { return nil }

        var mutable = itemType
        let mintResult = mintMissingIDs(in: &mutable.properties)
        let events = applyRelationTransforms(
            to: &mutable.properties, typeID: mutable.id, parentMap: parentMap)
        mutable.schemaVersion = currentTypeSchemaVersion
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
            updatedSchemaJSON: encoded,
            events: events
        )
    }

    /// Applies the two semantic relation transforms to `properties` in place:
    ///
    /// 1. **Collection → parent Type rewrite (lossless).** A property targeting
    ///    `.pageCollection(cid)` is repointed to `.pageType(parentID)` when the
    ///    parent resolves via `parentMap` (mirror for `.itemCollection`). An
    ///    unresolvable Collection (orphan / external) is left untouched — never
    ///    break a target we can't resolve.
    /// 2. **context_tier drop (lossy).** A user-created property targeting
    ///    `.contextTier(n)` is removed from the schema entirely. This drops only
    ///    the property *declaration* — tier VALUES live in the `tier1/2/3`
    ///    frontmatter root arrays and are untouched. The synthesized
    ///    `_tier1/_tier2/_tier3` rows are merged at runtime and never appear in
    ///    the stored `properties`, so they're never seen here.
    ///
    /// Order matters: rewrite first (mutates targets in place), then drop
    /// (removes entries). Returns the collected events for the TypeMigration.
    private static func applyRelationTransforms(
        to properties: inout [PropertyDefinition],
        typeID: String,
        parentMap: CollectionParentMap
    ) -> [MigrationEvent] {
        var events: [MigrationEvent] = []

        // Pass 1 — rewrite Collection targets in place.
        for idx in properties.indices {
            switch properties[idx].relationTarget {
            case .pageCollection(let cid):
                if let parentID = parentMap.pageCollections[cid] {
                    properties[idx].relationTarget = .pageType(parentID)
                    events.append(
                        .pageCollectionRewritten(
                            propertyID: properties[idx].id, from: cid, to: parentID))
                }
            case .itemCollection(let cid):
                if let parentID = parentMap.itemCollections[cid] {
                    properties[idx].relationTarget = .itemType(parentID)
                    events.append(
                        .itemCollectionRewritten(
                            propertyID: properties[idx].id, from: cid, to: parentID))
                }
            default:
                break
            }
        }

        // Pass 2 — drop context_tier declarations. Iterate indices in reverse so
        // removals don't invalidate not-yet-visited indices.
        for idx in properties.indices.reversed() {
            if case .contextTier(let tier) = properties[idx].relationTarget {
                events.append(
                    .contextTierDropped(
                        propertyID: properties[idx].id, tier: tier, typeID: typeID))
                properties.remove(at: idx)
            }
        }

        return events
    }

    /// Walks every root Type folder and its immediate sub-folders, recording
    /// each Collection's `id → parent Type id`. Malformed sidecars (or Types
    /// that fail to load) are skipped via `try?`/guard — never fatal, since the
    /// map is a best-effort lookup for relation rewriting.
    private static func buildCollectionParentMap(at nexusRoot: URL) -> CollectionParentMap {
        var map = CollectionParentMap.empty
        let fm = FileManager.default

        for typeFolder in enumerateRootTypeFolders(at: nexusRoot) {
            let pageSidecar = typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            let itemSidecar = typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)

            // Determine the parent Type's ID + which Collection sidecar to look
            // for in the sub-folders.
            let parentID: String
            let collectionSidecarName: String
            let isPage: Bool
            if fm.fileExists(atPath: pageSidecar.path) {
                guard let pt = try? PageType.load(from: pageSidecar) else { continue }
                parentID = pt.id
                collectionSidecarName = NexusPaths.pageCollectionSidecarFilename
                isPage = true
            } else if fm.fileExists(atPath: itemSidecar.path) {
                guard let it = try? ItemType.load(from: itemSidecar) else { continue }
                parentID = it.id
                collectionSidecarName = NexusPaths.itemCollectionSidecarFilename
                isPage = false
            } else {
                continue
            }

            guard
                let subEntries = try? fm.contentsOfDirectory(
                    at: typeFolder,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles])
            else { continue }

            for sub in subEntries {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue
                else { continue }
                let collectionSidecar = sub.appendingPathComponent(collectionSidecarName)
                guard fm.fileExists(atPath: collectionSidecar.path) else { continue }

                if isPage {
                    guard let c = try? PageCollection.load(from: collectionSidecar) else { continue }
                    map.pageCollections[c.id] = parentID
                } else {
                    guard let c = try? ItemCollection.load(from: collectionSidecar) else { continue }
                    map.itemCollections[c.id] = parentID
                }
            }
        }

        return map
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

    private static func applyItemType(_ migration: TypeMigration, into report: inout Report) {
        let txn = SchemaTransaction()
        txn.stage(payload: migration.updatedSchemaJSON, to: migration.sidecarURL)

        var memberCount = 0
        for itemURL in enumerateItemMembers(in: migration.typeFolderURL) {
            do {
                // Format-agnostic read: `.md` Items decode via the frontmatter
                // envelope, legacy `.json` Items via AtomicJSON — `Item.load`
                // dispatches on extension, so a `.md` member never hits a
                // JSON-on-markdown `dataCorrupted` error here.
                var item = try Item.load(from: itemURL)
                if rekey(properties: &item.properties, with: migration.nameToID) {
                    item.modifiedAt = Date()
                    // Re-stage in the member's OWN format so we never write a
                    // JSON blob into a `.md` file (or vice versa). A `.json`
                    // member re-encodes as `.json`; a `.md` member re-encodes
                    // through the preserving envelope so foreign frontmatter +
                    // body survive. ItemFormatMigration retires the `.json` arm.
                    let payload = try encodedItemMemberPayload(item, at: itemURL)
                    txn.stage(payload: payload, to: itemURL)
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

    /// Encodes a rewritten Item member in the on-disk format of its existing
    /// file. A `.json` member round-trips through `AtomicJSON` (its native
    /// shape); a `.md` member round-trips through the preserving YAML-envelope
    /// codec (`preservingFrom: url`), so any foreign frontmatter key + the
    /// Markdown body survive the property rekey. Single source for the
    /// per-format re-stage in `applyItemType`.
    private static func encodedItemMemberPayload(_ item: Item, at url: URL) throws -> Data {
        if url.pathExtension == "md" {
            return try AtomicYAMLMarkdown.encode(
                frontmatter: item.frontmatter, body: item.description,
                preservingFrom: url, modeledKeys: ItemFrontmatter.modeledKeys)
        }
        return try AtomicJSON.encode(item)
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

    private static func needsMigration(_ it: ItemType) -> Bool {
        it.schemaVersion < currentTypeSchemaVersion
            || it.properties.contains(where: { $0.id.isEmpty })
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
        enumerateMembers(in: typeFolder, withExtensions: ["md"])
    }

    /// Item members are format-agnostic: `.md` (canonical) + legacy `.json`,
    /// excluding per-kind sidecars (`_…`). The rekey pass reads each via
    /// `Item.load` and re-stages in its own format. `.md` support is required so
    /// a partially-migrated Type (some Items already `.md`) doesn't error when
    /// PropertyIDMigration re-runs over it (clobber-② fix).
    private static func enumerateItemMembers(in typeFolder: URL) -> [URL] {
        enumerateMembers(in: typeFolder, withExtensions: ["json", "md"]).filter {
            !$0.lastPathComponent.hasPrefix("_")
        }
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
