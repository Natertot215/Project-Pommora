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

    /// Creates a fresh PageType folder at the nexus root carrying a sidecar
    /// with the given properties. Optionally injects `schemaVersion` (default 0
    /// = "needs migration") via a raw JSON write.
    @discardableResult
    private static func makeLegacyPageType(
        in nexusRoot: URL,
        title: String,
        properties: [(name: String, type: PropertyType)],
        schemaVersion: Int = 0
    ) throws -> URL {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

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

    @discardableResult
    private static func makeLegacyItemType(
        in nexusRoot: URL,
        title: String,
        properties: [(name: String, type: PropertyType)]
    ) throws -> URL {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let propsJSON: [[String: Any]] = properties.map {
            ["id": "", "name": $0.name, "type": $0.type.rawValue]
        }
        let dict: [String: Any] = [
            "id": "01HIT\(UUID().uuidString.prefix(8))",
            "schema_version": 0,
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "properties": propsJSON,
            "views": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: sidecar, options: [.atomic])
        return folder
    }

    private static func writeLegacyItem(
        at url: URL,
        id: String,
        properties: [String: PropertyValue]
    ) throws {
        let now = Date()
        let item = Item(
            id: id, title: "", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: properties,
            createdAt: now, modifiedAt: now
        )
        try AtomicJSON.write(item, to: url)
    }

    // MARK: - PageType

    @Test func emptyNexusReportsNoOp() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }
        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.noOp)
        #expect(report.pageTypesScanned == 0)
        #expect(report.itemTypesScanned == 0)
    }

    @Test func migratesNameKeyedPageProperties() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeLegacyPageType(
            in: nexus, title: "Notes",
            properties: [("Status", .select), ("Tags", .multiSelect)])
        let pageURL = folder.appendingPathComponent("Page-1.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HPAGE1",
            properties: ["Status": .select("active"), "Tags": .multiSelect(["a", "b"])])

        let report = PropertyIDMigration.runIfNeeded(at: nexus)

        #expect(report.pageTypesScanned == 1)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 2)
        #expect(report.memberFilesRewritten == 1)
        #expect(report.failedTypes.isEmpty)

        // Verify schema gained prop_<ulid> IDs
        let pt = try PageType.load(from: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
        #expect(pt.schemaVersion == 1)
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

        let folder = try Self.makeLegacyPageType(
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

        let folder = try Self.makeLegacyPageType(
            in: nexus, title: "X", properties: [("Status", .select)])
        let pageURL = folder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01H1",
            properties: ["Status": .select("a"), "Ghost": .select("orphan")])

        _ = PropertyIDMigration.runIfNeeded(at: nexus)

        let pf = try PageFile.load(from: pageURL)
        // Known property rekeyed
        let pt = try PageType.load(from: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
        let statusID = pt.properties.first(where: { $0.name == "Status" })!.id
        #expect(pf.frontmatter.properties[statusID] == .select("a"))
        // Orphan preserved under its original key
        #expect(pf.frontmatter.properties["Ghost"] == .select("orphan"))
    }

    @Test func skipsAlreadyMigratedType() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // schemaVersion: 1 + every property already has a real id => no migration.
        let folder = nexus.appendingPathComponent("Pre-migrated", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let alreadyMigrated = PageType(
            id: "01HPT", title: "Pre-migrated", icon: nil,
            properties: [
                PropertyDefinition(id: "prop_01HEXISTING", name: "Status", type: .select)
            ],
            views: [], modifiedAt: Date()
        )
        try alreadyMigrated.save(to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.pageTypesScanned == 1)
        #expect(report.typesMigrated == 0)
        #expect(report.propertiesMinted == 0)
    }

    // MARK: - ItemType

    @Test func migratesNameKeyedItemProperties() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeLegacyItemType(
            in: nexus, title: "Bookmarks", properties: [("Stage", .select)])
        let itemURL = folder.appendingPathComponent("Swift-evolution.json")
        try Self.writeLegacyItem(
            at: itemURL, id: "01HITEM1", properties: ["Stage": .select("triaged")])

        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.itemTypesScanned == 1)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 1)
        #expect(report.memberFilesRewritten == 1)

        let it = try ItemType.load(from: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename))
        #expect(it.schemaVersion == 1)
        let stageID = it.properties.first!.id
        #expect(stageID.hasPrefix("prop_"))

        let item = try Item.load(from: itemURL)
        #expect(item.properties[stageID] == .select("triaged"))
        #expect(item.properties["Stage"] == nil)
    }

    @Test func ignoresSidecarFilesWhenEnumeratingItems() throws {
        // Sanity: _itemcollection.json sidecars should not be treated as Items.
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let typeFolder = try Self.makeLegacyItemType(
            in: nexus, title: "Books", properties: [("Genre", .select)])
        let collectionFolder = typeFolder.appendingPathComponent("Fiction", isDirectory: true)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        // Write a collection sidecar — must be skipped.
        let collection = ItemCollection(
            id: "01HC", typeID: "01HIT", title: "Fiction",
            folderURL: collectionFolder, modifiedAt: Date())
        try collection.save(to: collectionFolder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))

        // No actual items — migration should still succeed (schema-only rewrite)
        // and not blow up trying to decode the sidecar as an Item.
        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.itemTypesScanned == 1)
        #expect(report.typesMigrated == 1)
        #expect(report.failedTypes.isEmpty)
        #expect(report.memberFilesRewritten == 0)
    }
}
