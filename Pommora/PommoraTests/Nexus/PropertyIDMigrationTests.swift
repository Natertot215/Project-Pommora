import Foundation
import Testing

@testable import Pommora

@Suite("PropertyIDMigration") struct PropertyIDMigrationTests {

    // MARK: - Fixture helpers

    private static func makeTempNexus() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pommora-propid-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Creates a fresh PageCollection folder at the nexus root carrying a sidecar
    /// with the given properties. Optionally injects `schemaVersion` (default 0
    /// = "needs migration") via a raw JSON write.
    @discardableResult
    private static func makeLegacyPageCollection(
        in nexusRoot: URL,
        title: String,
        properties: [(name: String, type: PropertyType)],
        schemaVersion: Int = 0
    ) throws -> URL {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        // Write a raw legacy JSON shape: properties have empty id (or no id key
        // at all if schemaVersion < 1). Both produce id == "" after decode.
        let propsJSON: [[String: Any]] = properties.map {
            ["id": "", "name": $0.name, "type": $0.type.rawValue]
        }
        let dict: [String: Any] = [
            "id": "01HPT\(UUID().uuidString.prefix(8))",
            "schema_version": schemaVersion,
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "properties": propsJSON,
            "views": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: sidecar, options: [.atomic])
        return folder
    }

    /// Writes a legacy Page with name-keyed properties at the given URL.
    private static func writeLegacyPage(
        at url: URL,
        id: String,
        properties: [String: PropertyValue]
    ) throws {
        let fm = PageFrontmatter(
            id: id, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: properties,
            createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "body content\n", to: url)
    }

    // MARK: - PageCollection

    @Test func emptyNexusReportsNoOp() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }
        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.noOp)
        #expect(report.pageCollectionsScanned == 0)
    }

    @Test func migratesNameKeyedPageProperties() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeLegacyPageCollection(
            in: nexus, title: "Notes",
            properties: [("Status", .select), ("Tags", .multiSelect)])
        let pageURL = folder.appendingPathComponent("Page-1.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HPAGE1",
            properties: ["Status": .select("active"), "Tags": .multiSelect(["a", "b"])])

        let report = PropertyIDMigration.runIfNeeded(at: nexus)

        #expect(report.pageCollectionsScanned == 1)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 2)
        #expect(report.memberFilesRewritten == 1)
        #expect(report.failedTypes.isEmpty)

        // Verify schema gained prop_<ulid> IDs
        let pt = try PageCollection.load(from: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        #expect(pt.schemaVersion == 2)
        #expect(pt.properties.allSatisfy { $0.id.hasPrefix("prop_") })

        // Build name → id map from schema
        let map = Dictionary(uniqueKeysWithValues: pt.properties.map { ($0.name, $0.id) })

        // Verify Page frontmatter rekeyed
        let pf = try PageFile.load(from: pageURL)
        #expect(pf.frontmatter.properties[map["Status"]!] == .select("active"))
        #expect(pf.frontmatter.properties[map["Tags"]!] == .multiSelect(["a", "b"]))
        #expect(pf.frontmatter.properties["Status"] == nil)  // old key gone
    }

    @Test func idempotentReRunIsNoOp() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeLegacyPageCollection(
            in: nexus, title: "X", properties: [("S", .select)])
        let pageURL = folder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HX1", properties: ["S": .select("v")])

        _ = PropertyIDMigration.runIfNeeded(at: nexus)
        let second = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(second.noOp)
        #expect(second.typesMigrated == 0)
        #expect(second.propertiesMinted == 0)
        #expect(second.memberFilesRewritten == 0)
    }

    @Test func preservesOrphanPropertyKeys() throws {
        // Member file has a property key the schema doesn't know about.
        // Migration should preserve the orphan key as-is (don't drop data).
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeLegacyPageCollection(
            in: nexus, title: "X", properties: [("Status", .select)])
        let pageURL = folder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01H1",
            properties: ["Status": .select("a"), "Ghost": .select("orphan")])

        _ = PropertyIDMigration.runIfNeeded(at: nexus)

        let pf = try PageFile.load(from: pageURL)
        // Known property rekeyed
        let pt = try PageCollection.load(from: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        let statusID = pt.properties.first(where: { $0.name == "Status" })!.id
        #expect(pf.frontmatter.properties[statusID] == .select("a"))
        // Orphan preserved under its original key
        #expect(pf.frontmatter.properties["Ghost"] == .select("orphan"))
    }

    @Test func skipsAlreadyMigratedType() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // schemaVersion: 2 (init default) + every property already has a real id
        // => no migration.
        let folder = nexus.appendingPathComponent("Pre-migrated", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let alreadyMigrated = PageCollection(
            id: "01HPT", title: "Pre-migrated", icon: nil,
            properties: [
                PropertyDefinition(id: "prop_01HEXISTING", name: "Status", type: .select)
            ],
            views: [], modifiedAt: Date()
        )
        try alreadyMigrated.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.pageCollectionsScanned == 1)
        #expect(report.typesMigrated == 0)
        #expect(report.propertiesMinted == 0)
    }

    // MARK: - Phase C.5 scan/apply two-phase API

    @Test func scanEmptyNexusReturnsEmptyPlan() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }
        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(!plan.hasAnyMigration)
        #expect(plan.totalTypes == 0)
        #expect(plan.totalPropertiesToMint == 0)
        #expect(plan.totalMemberFileCandidates == 0)
        #expect(plan.pageCollectionMigrations.isEmpty)
    }

    @Test func scanReportsAccurateCountsBeforeApply() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let pageFolder = try Self.makeLegacyPageCollection(
            in: nexus, title: "Notes",
            properties: [("Status", .select), ("Tags", .multiSelect)])
        try Self.writeLegacyPage(
            at: pageFolder.appendingPathComponent("Page-1.md"),
            id: "01HPAGE1", properties: ["Status": .select("active")])
        try Self.writeLegacyPage(
            at: pageFolder.appendingPathComponent("Page-2.md"),
            id: "01HPAGE2", properties: ["Status": .select("done")])

        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(plan.hasAnyMigration)
        #expect(plan.totalTypes == 1)
        #expect(plan.totalPropertiesToMint == 2)  // Status + Tags
        #expect(plan.totalMemberFileCandidates == 2)  // 2 pages

        // Per-Type accuracy
        #expect(plan.pageCollectionMigrations.count == 1)
        #expect(plan.pageCollectionMigrations[0].propertiesToMint == 2)
        #expect(plan.pageCollectionMigrations[0].memberFileCandidates == 2)
        #expect(plan.pageCollectionMigrations[0].collectionTitle == "Notes")
    }

    @Test func scanIsPureNoDiskWrites() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let pageFolder = try Self.makeLegacyPageCollection(
            in: nexus, title: "Notes", properties: [("Status", .select)])
        let pageURL = pageFolder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HP", properties: ["Status": .select("v")])

        // Snapshot file contents before scan
        let pageContentBefore = try String(contentsOf: pageURL, encoding: .utf8)
        let sidecarURL = pageFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let sidecarContentBefore = try String(contentsOf: sidecarURL, encoding: .utf8)

        // Scan twice — both should be pure
        _ = PropertyIDMigration.scan(at: nexus)
        _ = PropertyIDMigration.scan(at: nexus)

        let pageContentAfter = try String(contentsOf: pageURL, encoding: .utf8)
        let sidecarContentAfter = try String(contentsOf: sidecarURL, encoding: .utf8)
        #expect(pageContentBefore == pageContentAfter)
        #expect(sidecarContentBefore == sidecarContentAfter)
    }

    @Test func applyExecutesScanPlan() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let pageFolder = try Self.makeLegacyPageCollection(
            in: nexus, title: "Notes", properties: [("Status", .select)])
        let pageURL = pageFolder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HP", properties: ["Status": .select("active")])

        let plan = PropertyIDMigration.scan(at: nexus)
        let report = PropertyIDMigration.apply(plan)

        #expect(report.pageCollectionsScanned == 1)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 1)
        #expect(report.memberFilesRewritten == 1)

        // Same end state as runIfNeeded would produce
        let pt = try PageCollection.load(from: pageFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        #expect(pt.schemaVersion == 2)
        let statusID = pt.properties.first(where: { $0.name == "Status" })!.id
        let pf = try PageFile.load(from: pageURL)
        #expect(pf.frontmatter.properties[statusID] == .select("active"))
    }

    @Test func scanAfterApplyIsEmpty() throws {
        // Apply migration via scan/apply; the next scan should return empty
        // (idempotent semantics preserved in the two-phase API).
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeLegacyPageCollection(
            in: nexus, title: "X", properties: [("S", .select)])
        try Self.writeLegacyPage(
            at: folder.appendingPathComponent("P.md"),
            id: "01HX", properties: ["S": .select("v")])

        let plan1 = PropertyIDMigration.scan(at: nexus)
        _ = PropertyIDMigration.apply(plan1)

        let plan2 = PropertyIDMigration.scan(at: nexus)
        #expect(!plan2.hasAnyMigration)
        #expect(plan2.totalTypes == 0)
    }

    // MARK: - schemaVersion 2 trigger (Relations redesign — normalizing re-save)

    /// Writes a v1 PageCollection sidecar: `schema_version: 1` with every property
    /// ID already minted. Pre-Relations-redesign this needed no migration; the
    /// broadened `< 2` trigger now re-saves it once to normalize the JSON.
    @discardableResult
    private static func makeV1PageCollection(
        in nexusRoot: URL,
        title: String,
        properties: [(id: String, name: String, type: PropertyType)]
    ) throws -> URL {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let propsJSON: [[String: Any]] = properties.map {
            ["id": $0.id, "name": $0.name, "type": $0.type.rawValue]
        }
        let dict: [String: Any] = [
            "id": "01HPT\(UUID().uuidString.prefix(8))",
            "schema_version": 1,
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "properties": propsJSON,
            "views": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: sidecar, options: [.atomic])
        return folder
    }

    @Test func v1SidecarReMigratesAndBumpsToVersion2() throws {
        // A v1 Type sidecar (schemaVersion 1, all IDs present) now triggers
        // migration so its JSON gets a normalizing re-save; the sidecar lands
        // at schemaVersion 2 after apply (no new property IDs minted).
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeV1PageCollection(
            in: nexus, title: "Notes",
            properties: [("prop_01HSTATUS", "Status", .select)])

        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(plan.hasAnyMigration)
        #expect(plan.pageCollectionMigrations.count == 1)
        #expect(plan.pageCollectionMigrations[0].propertiesToMint == 0)  // IDs already present

        let report = PropertyIDMigration.apply(plan)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 0)

        let pt = try PageCollection.load(from: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        #expect(pt.schemaVersion == 2)
        #expect(pt.properties.first?.id == "prop_01HSTATUS")  // preserved
    }

    @Test func freshPageCollectionIsSchemaVersion2() {
        // Newly-constructed Types are stamped current so they never re-migrate.
        let pt = PageCollection(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(pt.schemaVersion == 2)
    }

    // MARK: - Orphan user-relation clearing

    /// A member under a MIGRATING PageCollection carrying an orphaned `$rel`-keyed
    /// property (a `prop_`-prefixed key whose ID is absent from the post-migration
    /// schema) must have that entry dropped. The root `tier1` array and any
    /// foreign frontmatter are unaffected.
    @Test func clearOrphanRelationValuesOnPageMemberDuringMigration() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // Type with one legit property ("Status"); needs migration (schemaVersion 0).
        let folder = try Self.makeLegacyPageCollection(
            in: nexus, title: "Notes",
            properties: [("Status", .select)])

        // Write a page with:
        //   - name-keyed "Status" (will be rekeyed to prop_<ulid>)
        //   - orphaned prop_OLDREL with a .relation value (NOT in schema → must be cleared)
        //   - tier1 root array (must survive untouched)
        //   - body content (must survive)
        let pageURL = folder.appendingPathComponent("Page-1.md")
        let orphanRelKey = "prop_OLDREL_ORPHAN"
        let targetID = "01HTARGET01HTARGET01HTARGET"
        let areaID = "01HAREAX01HAREAX01HAREAX01H"
        let fm = PageFrontmatter(
            id: "01HPAGE1", icon: nil,
            tier1: [areaID], tier2: [], tier3: [],
            properties: [
                "Status": .select("active"),
                orphanRelKey: .relation([targetID]),
            ],
            createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "## Body survives\n", to: pageURL)

        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.typesMigrated == 1)
        #expect(report.memberFilesRewritten == 1)
        #expect(report.failedTypes.isEmpty)

        // Reload and assert:
        let pf = try PageFile.load(from: pageURL)

        // Orphan relation key must be gone.
        #expect(pf.frontmatter.properties[orphanRelKey] == nil, "orphaned $rel key must be cleared")

        // Legit property is rekeyed (not name-keyed any more, not the orphan key).
        let pt = try PageCollection.load(
            from: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        let statusID = pt.properties.first(where: { $0.name == "Status" })!.id
        #expect(pf.frontmatter.properties[statusID] == .select("active"), "legit property survives rekeyed")

        // Root tier array survives.
        #expect(pf.frontmatter.tier1 == [areaID], "root tier1 array must not be touched")

        // Body survives.
        #expect(pf.body.contains("Body survives"), "page body must survive the rewrite")
    }

}
