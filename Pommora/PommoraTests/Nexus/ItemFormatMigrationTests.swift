import Foundation
import Testing

@testable import Pommora

@Suite("ItemFormatMigration") struct ItemFormatMigrationTests {

    // MARK: - Fixture helpers

    private static func makeTempNexus() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pommora-itemfmt-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Creates a fresh ItemType folder at the nexus root carrying a minimal
    /// `_itemtype.json` sidecar (current schema version so PropertyIDMigration
    /// doesn't fight us — this suite tests format conversion only).
    @discardableResult
    private static func makeItemType(in nexusRoot: URL, title: String) throws -> URL {
        let folder = nexusRoot.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let dict: [String: Any] = [
            "id": "01HIT\(UUID().uuidString.prefix(8))",
            "schema_version": 2,
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "properties": [],
            "views": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: sidecar, options: [.atomic])
        return folder
    }

    /// Creates an ItemCollection sub-folder inside `typeFolder` carrying its
    /// `_itemcollection.json` sidecar (mirrors PropertyIDMigrationTests'
    /// `writeItemCollection`). Returns the sub-folder URL.
    @discardableResult
    private static func makeItemCollection(
        in typeFolder: URL, parentTypeID: String, title: String
    ) throws -> URL {
        let folder = typeFolder.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let collection = ItemCollection(
            id: "01HIC\(UUID().uuidString.prefix(8))", typeID: parentTypeID, title: title,
            folderURL: folder, modifiedAt: Date())
        try collection.save(
            to: folder.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        return folder
    }

    /// Writes a real `.json` Item via `AtomicJSON.write` (the production writer)
    /// at `folder/<title>.json`.
    @discardableResult
    private static func writeJSONItem(
        title: String,
        in folder: URL,
        id: String,
        icon: String? = nil,
        description: String = "",
        tier1: [String] = [],
        properties: [String: PropertyValue] = [:]
    ) throws -> URL {
        let now = Date()
        let item = Item(
            id: id, title: title, icon: icon, description: description,
            tier1: tier1, tier2: [], tier3: [],
            properties: properties,
            createdAt: now, modifiedAt: now)
        let url = folder.appendingPathComponent("\(title).json", isDirectory: false)
        try AtomicJSON.write(item, to: url)
        return url
    }

    /// Writes a `.md` Item twin via the production `Item.save` path.
    @discardableResult
    private static func writeMarkdownItem(
        title: String,
        in folder: URL,
        id: String,
        description: String = "",
        properties: [String: PropertyValue] = [:]
    ) throws -> URL {
        let now = Date()
        let item = Item(
            id: id, title: title, icon: nil, description: description,
            tier1: [], tier2: [], tier3: [],
            properties: properties,
            createdAt: now, modifiedAt: now)
        let url = NexusPaths.itemFileURL(forTitle: title, in: folder)
        try item.save(to: url)
        return url
    }

    /// True iff anything sits under the nexus `.trash/` directory.
    private static func trashContents(in nexusRoot: URL) -> [URL] {
        let trash = nexusRoot.appendingPathComponent(".trash", isDirectory: true)
        let e = FileManager.default.enumerator(at: trash, includingPropertiesForKeys: nil)
        var out: [URL] = []
        while let url = e?.nextObject() as? URL { out.append(url) }
        return out
    }

    // MARK: - Core conversion

    @Test func convertsJSONItemToMarkdownTwinAndTrashesJSON() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeItemType(in: nexus, title: "Bookmarks")
        // id + properties (select + relation `$rel`-shaped) + a tier value +
        // a non-empty description body — the full fidelity surface.
        let jsonURL = try Self.writeJSONItem(
            title: "Swift-Evolution",
            in: folder,
            id: "01HITEM1",
            icon: "star",
            description: "A long-form note body that must survive the format flip.",
            tier1: ["01HTIER1"],
            properties: [
                "prop_stage": .select("triaged"),
                "prop_links": .relation(["01HREL1", "01HREL2"]),
            ])

        let report = ItemFormatMigration.runIfNeeded(at: nexus)
        #expect(report.itemTypesScanned == 1)
        #expect(report.itemsConverted == 1)
        #expect(report.leftoversCleaned == 0)
        #expect(report.failedItems.isEmpty)

        // `.md` twin exists; `.json` is gone (trashed, not orphaned).
        let mdURL = NexusPaths.itemFileURL(forTitle: "Swift-Evolution", in: folder)
        #expect(Filesystem.fileExists(at: mdURL))
        #expect(!Filesystem.fileExists(at: jsonURL))

        // The original `.json` is recoverable in `.trash/`, not hard-deleted.
        let trashedJSON = Self.trashContents(in: nexus).filter { $0.pathExtension == "json" }
        #expect(trashedJSON.count == 1)

        // Round-trip the `.md`: id / icon / properties / relation / tier / body intact.
        let loaded = try Item.load(from: mdURL)
        #expect(loaded.id == "01HITEM1")
        #expect(loaded.icon == "star")
        #expect(loaded.description == "A long-form note body that must survive the format flip.")
        #expect(loaded.tier1 == ["01HTIER1"])
        #expect(loaded.properties["prop_stage"] == .select("triaged"))
        #expect(loaded.properties["prop_links"] == .relation(["01HREL1", "01HREL2"]))
    }

    // MARK: - Collection-nested member

    @Test func convertsJSONItemNestedInCollectionSubfolderInPlace() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // ItemType at the root, with an ItemCollection sub-folder. The `.json`
        // Item lives INSIDE the Collection sub-folder, not at the Type root.
        let typeFolder = try Self.makeItemType(in: nexus, title: "Library")
        let typeID = try ItemType.load(
            from: typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        ).id
        let collectionFolder = try Self.makeItemCollection(
            in: typeFolder, parentTypeID: typeID, title: "Sci-Fi")

        let jsonURL = try Self.writeJSONItem(
            title: "Note", in: collectionFolder, id: "01HNESTED",
            icon: "book",
            description: "a nested-collection member body",
            tier1: ["01HTIERX"],
            properties: ["prop_rating": .select("five")])

        let report = ItemFormatMigration.runIfNeeded(at: nexus)
        #expect(report.itemTypesScanned == 1)
        #expect(report.itemsConverted == 1)
        #expect(report.leftoversCleaned == 0)
        #expect(report.failedItems.isEmpty)

        // The `.md` twin lands in the SAME Collection sub-folder, NOT the Type
        // root; the `.json` is trashed (not orphaned).
        let mdURL = NexusPaths.itemFileURL(forTitle: "Note", in: collectionFolder)
        #expect(Filesystem.fileExists(at: mdURL))
        #expect(!Filesystem.fileExists(at: jsonURL))
        // No stray twin leaked up to the Type root.
        #expect(!Filesystem.fileExists(at: NexusPaths.itemFileURL(forTitle: "Note", in: typeFolder)))

        // Original `.json` is recoverable in `.trash/`.
        let trashedJSON = Self.trashContents(in: nexus).filter { $0.pathExtension == "json" }
        #expect(trashedJSON.count == 1)

        // id / icon / properties / tier / body all intact through the flip.
        let loaded = try Item.load(from: mdURL)
        #expect(loaded.id == "01HNESTED")
        #expect(loaded.icon == "book")
        #expect(loaded.description == "a nested-collection member body")
        #expect(loaded.tier1 == ["01HTIERX"])
        #expect(loaded.properties["prop_rating"] == .select("five"))
    }

    // MARK: - Idempotence

    @Test func secondRunIsNoOp() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeItemType(in: nexus, title: "Bookmarks")
        try Self.writeJSONItem(
            title: "Item-A", in: folder, id: "01HA",
            description: "body", properties: ["prop_x": .select("v")])

        let first = ItemFormatMigration.runIfNeeded(at: nexus)
        #expect(first.itemsConverted == 1)
        #expect(first.failedItems.isEmpty)

        let mdURL = NexusPaths.itemFileURL(forTitle: "Item-A", in: folder)
        let firstBytes = try Data(contentsOf: mdURL)

        // Second run: no `.json` left → plan is empty → no-op, no double-write.
        let plan = ItemFormatMigration.scan(at: nexus)
        #expect(!plan.hasAnyConversion)
        let second = ItemFormatMigration.runIfNeeded(at: nexus)
        #expect(second.noOp)
        #expect(second.itemsConverted == 0)
        #expect(second.leftoversCleaned == 0)
        #expect(second.failedItems.isEmpty)

        // The `.md` was not rewritten.
        let secondBytes = try Data(contentsOf: mdURL)
        #expect(firstBytes == secondBytes)
    }

    // MARK: - Interrupt / resume

    @Test func resumesPartialRunConvertingOnlyUnmigratedItems() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeItemType(in: nexus, title: "Bookmarks")

        // Already-migrated: a `.md` twin present alongside a leftover `.json`
        // sharing the title (a crash window between md-commit and json-trash).
        try Self.writeMarkdownItem(
            title: "Already", in: folder, id: "01HMD",
            description: "already migrated body", properties: ["prop_done": .select("yes")])
        let leftoverJSON = try Self.writeJSONItem(
            title: "Already", in: folder, id: "01HMD", description: "stale json body")
        let alreadyMD = NexusPaths.itemFileURL(forTitle: "Already", in: folder)
        let alreadyBytesBefore = try Data(contentsOf: alreadyMD)

        // Un-migrated: a lone `.json` that still needs converting.
        let pendingJSON = try Self.writeJSONItem(
            title: "Pending", in: folder, id: "01HJSON",
            description: "pending body", properties: ["prop_p": .select("waiting")])

        let report = ItemFormatMigration.runIfNeeded(at: nexus)
        #expect(report.failedItems.isEmpty)
        // One fresh conversion (Pending) + one leftover cleanup (Already's json).
        #expect(report.itemsConverted == 1)
        #expect(report.leftoversCleaned == 1)

        // The un-migrated one converted; its `.json` is gone.
        let pendingMD = NexusPaths.itemFileURL(forTitle: "Pending", in: folder)
        #expect(Filesystem.fileExists(at: pendingMD))
        #expect(!Filesystem.fileExists(at: pendingJSON))
        #expect(try Item.load(from: pendingMD).description == "pending body")

        // The already-migrated `.md` is byte-untouched; its leftover `.json` is
        // cleaned up (trashed).
        #expect(try Data(contentsOf: alreadyMD) == alreadyBytesBefore)
        #expect(!Filesystem.fileExists(at: leftoverJSON))
    }

    // MARK: - Failure isolation

    @Test func malformedJSONIsReportedAndDoesNotAbortBatch() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        let folder = try Self.makeItemType(in: nexus, title: "Bookmarks")

        // A malformed `.json` (not a valid Item) — must be reported, not thrown.
        let badURL = folder.appendingPathComponent("Broken.json", isDirectory: false)
        try Data("{ this is not valid json".utf8).write(to: badURL, options: [.atomic])

        // A healthy sibling that must still convert.
        let goodJSON = try Self.writeJSONItem(
            title: "Healthy", in: folder, id: "01HGOOD", description: "good body")

        let report = ItemFormatMigration.runIfNeeded(at: nexus)

        // The bad one is reported, NOT thrown; the batch continued.
        #expect(report.failedItems.count == 1)
        #expect(report.failedItems.first?.itemURL.lastPathComponent == "Broken.json")
        #expect(report.itemsConverted == 1)

        // The healthy sibling converted; the malformed file was left in place
        // (not trashed, not converted) for inspection.
        let goodMD = NexusPaths.itemFileURL(forTitle: "Healthy", in: folder)
        #expect(Filesystem.fileExists(at: goodMD))
        #expect(!Filesystem.fileExists(at: goodJSON))
        #expect(Filesystem.fileExists(at: badURL))
    }

    // MARK: - Site ② format-agnostic (PropertyIDMigration.applyItemType)

    @Test func propertyIDMigrationReadsMarkdownMemberAndReStagesAsMarkdown() throws {
        let nexus = try Self.makeTempNexus()
        defer { try? FileManager.default.removeItem(at: nexus) }

        // A legacy ItemType (schema_version 0, name-keyed property, empty id) so
        // PropertyIDMigration mints an id + rekeys members. Mix a `.md` member
        // and a `.json` member: the `.md` must be READ via Item.load (no
        // dataCorrupted) and RE-STAGED as `.md`; the `.json` re-stages as `.json`.
        let folder = nexus.appendingPathComponent("Bookmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        let dict: [String: Any] = [
            "id": "01HITLEGACY",
            "schema_version": 0,
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "properties": [["id": "", "name": "Stage", "type": PropertyType.select.rawValue]],
            "views": [],
        ]
        try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            .write(to: sidecar, options: [.atomic])

        // `.md` member with a name-keyed `Stage` property + a body.
        let mdURL = try Self.writeMarkdownItem(
            title: "MarkdownItem", in: folder, id: "01HMDMEMBER",
            description: "markdown member body", properties: ["Stage": .select("md-val")])
        // `.json` member with the same name-keyed property.
        let jsonURL = try Self.writeJSONItem(
            title: "JsonItem", in: folder, id: "01HJSONMEMBER",
            description: "json member body", properties: ["Stage": .select("json-val")])

        let report = PropertyIDMigration.runIfNeeded(at: nexus)
        #expect(report.failedTypes.isEmpty)
        #expect(report.typesMigrated == 1)
        #expect(report.propertiesMinted == 1)
        // Both members rekeyed.
        #expect(report.memberFilesRewritten == 2)

        let it = try ItemType.load(from: sidecar)
        let stageID = try #require(it.properties.first?.id)
        #expect(stageID.hasPrefix("prop_"))

        // `.md` member: still `.md`, body intact, property rekeyed by ID.
        #expect(Filesystem.fileExists(at: mdURL))
        let mdRaw = try String(contentsOf: mdURL, encoding: .utf8)
        #expect(mdRaw.hasPrefix("---\n"))  // re-staged as a YAML envelope, not JSON.
        let mdItem = try Item.load(from: mdURL)
        #expect(mdItem.description == "markdown member body")
        #expect(mdItem.properties[stageID] == .select("md-val"))
        #expect(mdItem.properties["Stage"] == nil)

        // `.json` member: still `.json` (NOT converted by PropertyIDMigration —
        // that is ItemFormatMigration's job), property rekeyed by ID.
        #expect(Filesystem.fileExists(at: jsonURL))
        let jsonRaw = try String(contentsOf: jsonURL, encoding: .utf8)
        #expect(jsonRaw.hasPrefix("{"))  // re-staged as JSON, not an envelope.
        let jsonItem = try Item.load(from: jsonURL)
        #expect(jsonItem.description == "json member body")
        #expect(jsonItem.properties[stageID] == .select("json-val"))
        #expect(jsonItem.properties["Stage"] == nil)
    }
}
