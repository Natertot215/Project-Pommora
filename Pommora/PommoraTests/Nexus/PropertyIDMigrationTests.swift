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

        // schemaVersion: 2 (init default) + every property already has a real id
        // => no migration.
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
        #expect(it.schemaVersion == 2)
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

    // MARK: - Phase C.5 scan/apply two-phase API

    @Test func scanEmptyNexusReturnsEmptyPlan() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }
        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(!plan.hasAnyMigration)
        #expect(plan.totalTypes == 0)
        #expect(plan.totalPropertiesToMint == 0)
        #expect(plan.totalMemberFileCandidates == 0)
        #expect(plan.pageTypeMigrations.isEmpty)
        #expect(plan.itemTypeMigrations.isEmpty)
    }

    @Test func scanReportsAccurateCountsBeforeApply() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let pageFolder = try Self.makeLegacyPageType(
            in: nexus, title: "Notes",
            properties: [("Status", .select), ("Tags", .multiSelect)])
        try Self.writeLegacyPage(
            at: pageFolder.appendingPathComponent("Page-1.md"),
            id: "01HPAGE1", properties: ["Status": .select("active")])
        try Self.writeLegacyPage(
            at: pageFolder.appendingPathComponent("Page-2.md"),
            id: "01HPAGE2", properties: ["Status": .select("done")])

        let itemFolder = try Self.makeLegacyItemType(
            in: nexus, title: "Bookmarks", properties: [("Stage", .select)])
        try Self.writeLegacyItem(
            at: itemFolder.appendingPathComponent("Book-1.json"),
            id: "01HBOOK1", properties: ["Stage": .select("queue")])

        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(plan.hasAnyMigration)
        #expect(plan.totalTypes == 2)
        #expect(plan.totalPropertiesToMint == 3)  // Status + Tags + Stage
        #expect(plan.totalMemberFileCandidates == 3)  // 2 pages + 1 item

        // Per-Type accuracy
        #expect(plan.pageTypeMigrations.count == 1)
        #expect(plan.pageTypeMigrations[0].propertiesToMint == 2)
        #expect(plan.pageTypeMigrations[0].memberFileCandidates == 2)
        #expect(plan.pageTypeMigrations[0].typeTitle == "Notes")
        #expect(plan.itemTypeMigrations.count == 1)
        #expect(plan.itemTypeMigrations[0].propertiesToMint == 1)
        #expect(plan.itemTypeMigrations[0].memberFileCandidates == 1)
        #expect(plan.itemTypeMigrations[0].typeTitle == "Bookmarks")
    }

    @Test func scanIsPureNoDiskWrites() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let pageFolder = try Self.makeLegacyPageType(
            in: nexus, title: "Notes", properties: [("Status", .select)])
        let pageURL = pageFolder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HP", properties: ["Status": .select("v")])

        // Snapshot file contents before scan
        let pageContentBefore = try String(contentsOf: pageURL, encoding: .utf8)
        let sidecarURL = pageFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
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

        let pageFolder = try Self.makeLegacyPageType(
            in: nexus, title: "Notes", properties: [("Status", .select)])
        let pageURL = pageFolder.appendingPathComponent("P.md")
        try Self.writeLegacyPage(
            at: pageURL, id: "01HP", properties: ["Status": .select("active")])

        let plan = PropertyIDMigration.scan(at: nexus)
        let report = PropertyIDMigration.apply(plan)

        #expect(report.pageTypesScanned == 1)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 1)
        #expect(report.memberFilesRewritten == 1)

        // Same end state as runIfNeeded would produce
        let pt = try PageType.load(from: pageFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
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

        let folder = try Self.makeLegacyPageType(
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

    /// Writes a v1 PageType sidecar: `schema_version: 1` with every property
    /// ID already minted. Pre-Relations-redesign this needed no migration; the
    /// broadened `< 2` trigger now re-saves it once to normalize the JSON.
    @discardableResult
    private static func makeV1PageType(
        in nexusRoot: URL,
        title: String,
        properties: [(id: String, name: String, type: PropertyType)]
    ) throws -> URL {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
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

        let folder = try Self.makeV1PageType(
            in: nexus, title: "Notes",
            properties: [("prop_01HSTATUS", "Status", .select)])

        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(plan.hasAnyMigration)
        #expect(plan.pageTypeMigrations.count == 1)
        #expect(plan.pageTypeMigrations[0].propertiesToMint == 0)  // IDs already present

        let report = PropertyIDMigration.apply(plan)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 0)

        let pt = try PageType.load(from: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
        #expect(pt.schemaVersion == 2)
        #expect(pt.properties.first?.id == "prop_01HSTATUS")  // preserved
    }

    @Test func freshPageTypeIsSchemaVersion2() {
        // Newly-constructed Types are stamped current so they never re-migrate.
        let pt = PageType(
            id: "01HP", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(pt.schemaVersion == 2)
    }

    @Test func freshItemTypeIsSchemaVersion2() {
        let it = ItemType(
            id: "01HI", title: "X", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        #expect(it.schemaVersion == 2)
    }

    @Test func planAllEventsEmptyForPlainIDMintMigration() throws {
        // A plain ID-mint / version-bump migration (no Collection or
        // context_tier relation targets) carries no MigrationEvents.
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        try Self.makeLegacyPageType(
            in: nexus, title: "Notes", properties: [("Status", .select)])
        try Self.makeLegacyItemType(
            in: nexus, title: "Bookmarks", properties: [("Stage", .select)])

        let plan = PropertyIDMigration.scan(at: nexus)
        #expect(plan.hasAnyMigration)
        #expect(plan.allEvents.isEmpty)
    }

    // MARK: - Relation transforms (Collection→Type rewrite + context_tier drop)

    /// Decodes a TypeMigration's staged `updatedSchemaJSON` (pre-apply `Data`)
    /// with the same ISO-8601 date strategy AtomicJSON uses on disk. The decoded
    /// `title` is "" (derived from folder name only by `load(from:)`), so assert
    /// on property `id`s rather than title.
    private static func decodeStaged<T: Codable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    /// Persists a PageType value at `<nexus>/<title>/_pagetype.json` with
    /// `schemaVersion: 1` (so it migrates) and the given properties — including
    /// any `relationTarget`s, encoded through PageType's real encoder. Returns
    /// the parent PageType's ULID.
    @discardableResult
    private static func writeRelationPageType(
        in nexusRoot: URL,
        title: String,
        properties: [PropertyDefinition]
    ) throws -> (folder: URL, typeID: String) {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let typeID = "01HPT\(UUID().uuidString.prefix(8))"
        let pt = PageType(
            id: typeID, title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date(),
            schemaVersion: 1)
        try pt.save(to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))
        return (folder, typeID)
    }

    /// Mirror of `writeRelationPageType` for ItemType.
    @discardableResult
    private static func writeRelationItemType(
        in nexusRoot: URL,
        title: String,
        properties: [PropertyDefinition]
    ) throws -> (folder: URL, typeID: String) {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let typeID = "01HIT\(UUID().uuidString.prefix(8))"
        let it = ItemType(
            id: typeID, title: title, icon: nil,
            properties: properties, views: [], modifiedAt: Date(),
            schemaVersion: 1)
        try it.save(to: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename))
        return (folder, typeID)
    }

    /// Creates a PageCollection sub-folder inside `typeFolder` and persists its
    /// `_pagecollection.json` sidecar. Returns the Collection's ULID.
    @discardableResult
    private static func writePageCollection(
        in typeFolder: URL, parentTypeID: String, title: String
    ) throws -> String {
        let folder = typeFolder.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let collectionID = "01HPC\(UUID().uuidString.prefix(8))"
        let collection = PageCollection(
            id: collectionID, typeID: parentTypeID, title: title,
            folderURL: folder, modifiedAt: Date())
        try collection.save(to: folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))
        return collectionID
    }

    /// Mirror of `writePageCollection` for ItemCollection.
    @discardableResult
    private static func writeItemCollection(
        in typeFolder: URL, parentTypeID: String, title: String
    ) throws -> String {
        let folder = typeFolder.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let collectionID = "01HIC\(UUID().uuidString.prefix(8))"
        let collection = ItemCollection(
            id: collectionID, typeID: parentTypeID, title: title,
            folderURL: folder, modifiedAt: Date())
        try collection.save(to: folder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        return collectionID
    }

    @Test func rewritesPageCollectionTargetToParentPageType() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // "Books" PageType with a "Fiction" PageCollection sub-folder.
        let books = try Self.writeRelationPageType(in: nexus, title: "Books", properties: [])
        let fictionID = try Self.writePageCollection(
            in: books.folder, parentTypeID: books.typeID, title: "Fiction")

        // A second PageType "Notes" carries a relation property pointed at the
        // Fiction collection — that target must rewrite to the Books type.
        let relProp = PropertyDefinition(
            id: "prop_01HREL", name: "Reading", type: .relation,
            relationTarget: .pageCollection(fictionID))
        let notes = try Self.writeRelationPageType(
            in: nexus, title: "Notes", properties: [relProp])

        let plan = PropertyIDMigration.scan(at: nexus)

        // Find the Notes migration and assert its event + rewritten target.
        let notesMig = try #require(
            plan.pageTypeMigrations.first(where: { $0.typeTitle == "Notes" }))
        #expect(
            notesMig.events.contains(
                .pageCollectionRewritten(propertyID: "prop_01HREL", from: fictionID, to: books.typeID)
            ))

        let decoded = try Self.decodeStaged(PageType.self, notesMig.updatedSchemaJSON)
        let prop = try #require(decoded.properties.first(where: { $0.id == "prop_01HREL" }))
        #expect(prop.relationTarget == .pageType(books.typeID))
        _ = notes  // silence unused warning
    }

    @Test func rewritesItemCollectionTargetToParentItemType() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let library = try Self.writeRelationItemType(in: nexus, title: "Library", properties: [])
        let sciFiID = try Self.writeItemCollection(
            in: library.folder, parentTypeID: library.typeID, title: "SciFi")

        let relProp = PropertyDefinition(
            id: "prop_01HIREL", name: "Sourced", type: .relation,
            relationTarget: .itemCollection(sciFiID))
        try Self.writeRelationItemType(in: nexus, title: "Sources", properties: [relProp])

        let plan = PropertyIDMigration.scan(at: nexus)

        let sourcesMig = try #require(
            plan.itemTypeMigrations.first(where: { $0.typeTitle == "Sources" }))
        #expect(
            sourcesMig.events.contains(
                .itemCollectionRewritten(propertyID: "prop_01HIREL", from: sciFiID, to: library.typeID)
            ))

        let decoded = try Self.decodeStaged(ItemType.self, sourcesMig.updatedSchemaJSON)
        let prop = try #require(decoded.properties.first(where: { $0.id == "prop_01HIREL" }))
        #expect(prop.relationTarget == .itemType(library.typeID))
    }

    @Test func dropsContextTierRelationProperty() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // A user property pointed at a context tier must be dropped from the
        // schema; a sibling normal property must survive.
        let tierProp = PropertyDefinition(
            id: "prop_01HTIER", name: "Linked Topic", type: .relation,
            relationTarget: .contextTier(2))
        let keepProp = PropertyDefinition(
            id: "prop_01HKEEP", name: "Status", type: .select)
        let result = try Self.writeRelationPageType(
            in: nexus, title: "Tasks", properties: [tierProp, keepProp])

        let plan = PropertyIDMigration.scan(at: nexus)

        let mig = try #require(
            plan.pageTypeMigrations.first(where: { $0.typeTitle == "Tasks" }))
        #expect(
            mig.events.contains(
                .contextTierDropped(propertyID: "prop_01HTIER", tier: 2, typeID: result.typeID)))

        let decoded = try Self.decodeStaged(PageType.self, mig.updatedSchemaJSON)
        #expect(!decoded.properties.contains(where: { $0.id == "prop_01HTIER" }))
        #expect(decoded.properties.contains(where: { $0.id == "prop_01HKEEP" }))  // sibling preserved
    }

    @Test func normalRelationTargetsProduceNoTransformEvents() throws {
        // Control: a Type whose relation targets are already plain .pageType /
        // .itemType produces no rewrite/drop events.
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let pageRel = PropertyDefinition(
            id: "prop_01HPAGE", name: "Page Ref", type: .relation,
            relationTarget: .pageType("01HSOMEPAGETYPE"))
        let itemRel = PropertyDefinition(
            id: "prop_01HITEM", name: "Item Ref", type: .relation,
            relationTarget: .itemType("01HSOMEITEMTYPE"))
        try Self.writeRelationPageType(
            in: nexus, title: "Mixed", properties: [pageRel, itemRel])

        let plan = PropertyIDMigration.scan(at: nexus)

        let mig = try #require(
            plan.pageTypeMigrations.first(where: { $0.typeTitle == "Mixed" }))
        #expect(mig.events.isEmpty)
        // Targets untouched.
        let decoded = try Self.decodeStaged(PageType.self, mig.updatedSchemaJSON)
        #expect(decoded.properties.count == 2)
        #expect(
            decoded.properties.first(where: { $0.id == "prop_01HPAGE" })?.relationTarget
                == .pageType("01HSOMEPAGETYPE"))
    }

    @Test func orphanCollectionTargetIsLeftUnchanged() throws {
        // A .pageCollection target whose collection isn't in the map (orphan /
        // external) must be left untouched — never break an unresolvable target.
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let orphanRel = PropertyDefinition(
            id: "prop_01HORPH", name: "Dangling", type: .relation,
            relationTarget: .pageCollection("01HCNOTREAL"))
        try Self.writeRelationPageType(
            in: nexus, title: "Orphans", properties: [orphanRel])

        let plan = PropertyIDMigration.scan(at: nexus)

        let mig = try #require(
            plan.pageTypeMigrations.first(where: { $0.typeTitle == "Orphans" }))
        #expect(mig.events.isEmpty)
        let decoded = try Self.decodeStaged(PageType.self, mig.updatedSchemaJSON)
        #expect(
            decoded.properties.first(where: { $0.id == "prop_01HORPH" })?.relationTarget
                == .pageCollection("01HCNOTREAL"))
    }

    @Test func planAllEventsAggregatesAcrossTypes() throws {
        // scan should flatten events from multiple migrating Types into allEvents.
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // Books + Fiction collection; Notes points a relation at Fiction.
        let books = try Self.writeRelationPageType(in: nexus, title: "Books", properties: [])
        let fictionID = try Self.writePageCollection(
            in: books.folder, parentTypeID: books.typeID, title: "Fiction")
        let pageRel = PropertyDefinition(
            id: "prop_01HPC", name: "Reading", type: .relation,
            relationTarget: .pageCollection(fictionID))
        try Self.writeRelationPageType(in: nexus, title: "Notes", properties: [pageRel])

        // A separate ItemType drops a context_tier property.
        let tierProp = PropertyDefinition(
            id: "prop_01HTIER", name: "Linked Space", type: .relation,
            relationTarget: .contextTier(1))
        let agendaLike = try Self.writeRelationItemType(
            in: nexus, title: "Tasks", properties: [tierProp])

        let plan = PropertyIDMigration.scan(at: nexus)

        #expect(
            plan.allEvents.contains(
                .pageCollectionRewritten(propertyID: "prop_01HPC", from: fictionID, to: books.typeID)))
        #expect(
            plan.allEvents.contains(
                .contextTierDropped(propertyID: "prop_01HTIER", tier: 1, typeID: agendaLike.typeID)))
        #expect(plan.allEvents.count == 2)
    }
}
