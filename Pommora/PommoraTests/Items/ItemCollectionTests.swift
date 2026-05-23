import Foundation
import Testing

@testable import Pommora

@Suite("ItemCollectionFile")
struct ItemCollectionTests {

    @Test("ItemCollection round-trips through _schema.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Errands", isDirectory: true)
            .appendingPathComponent("Groceries", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        let original = ItemCollection(
            id: "01HICOLL",
            typeID: "01HITYPE",
            title: "Groceries",
            folderURL: folder,
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.id == "01HICOLL")
        #expect(loaded.typeID == "01HITYPE")
        #expect(loaded.title == "Groceries")
        #expect(loaded.folderURL == folder)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("ItemCollection on-disk JSON uses snake_case for type_id + modified_at")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("T", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try ItemCollection(
            id: "01H", typeID: "01HT", title: "C",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"type_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(!raw.contains("\"typeID\""))
        #expect(!raw.contains("\"title\""))  // title not persisted
        #expect(!raw.contains("\"folderURL\""))  // folderURL not persisted
    }

    @Test("ItemCollection title derives from parent folder name on load")
    func titleFromFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("T", isDirectory: true)
            .appendingPathComponent("Side Sets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try ItemCollection(
            id: "01H", typeID: "01HT", title: "Side Sets",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.title == "Side Sets")
    }

    @Test("ItemCollection folderURL derives from metadata URL parent on load")
    func folderURLDerived() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("T", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try ItemCollection(
            id: "01H", typeID: "01HT", title: "X",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.folderURL == folder)
    }

    @Test("ItemCollection persists item_order when present")
    func itemOrderPersists() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("T", isDirectory: true)
            .appendingPathComponent("Ordered", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try ItemCollection(
            id: "01H", typeID: "01HT", title: "Ordered",
            folderURL: folder, modifiedAt: Date(),
            itemOrder: ["01HA", "01HB"]
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"item_order\""))

        let loaded = try ItemCollection.load(from: metaURL)
        #expect(loaded.itemOrder == ["01HA", "01HB"])
    }
}
