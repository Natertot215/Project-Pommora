import Foundation
import Testing

@testable import Pommora

@Suite("ItemTypeFile")
struct ItemTypeTests {

    @Test("ItemType round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        let original = ItemType(
            id: "01HITYPE",
            title: "Errands",
            icon: "cart",
            properties: [
                PropertyDefinition(
                    name: "status",
                    type: .select,
                    selectOptions: [
                        PropertyDefinition.SelectOption(value: "todo", label: "To do", color: .blue),
                        PropertyDefinition.SelectOption(value: "done", label: "Done", color: .gray),
                    ]
                ),
                PropertyDefinition(name: "due", type: .date, dateIncludesTime: false),
            ],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try ItemType.load(from: metaURL)
        #expect(loaded.id == "01HITYPE")
        #expect(loaded.title == "Errands")
        #expect(loaded.icon == "cart")
        #expect(loaded.properties.count == 2)
        #expect(loaded.properties[0].name == "status")
        #expect(loaded.properties[0].type == .select)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("ItemType on-disk JSON omits title (filename = title)")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Shopping", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try ItemType(id: "01H", title: "Shopping", icon: nil, properties: [], views: [], modifiedAt: Date())
            .save(to: metaURL)
        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("ItemType title derives from parent folder name on load")
    func titleFromFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Side Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        // Save with one in-memory title, then verify load derives from folder.
        try ItemType(
            id: "01H", title: "Side Errands", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try ItemType.load(from: metaURL)
        #expect(loaded.title == "Side Errands")
    }

    @Test("ItemType on-disk JSON uses snake_case for modified_at + order fields")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("E", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try ItemType(
            id: "01H", title: "E", icon: nil,
            properties: [], views: [], modifiedAt: Date(),
            collectionOrder: ["01HA"], itemOrder: ["01HB"]
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"modified_at\""))
        #expect(raw.contains("\"collection_order\""))
        #expect(raw.contains("\"item_order\""))
        #expect(!raw.contains("\"modifiedAt\""))
        #expect(!raw.contains("\"collectionOrder\""))
    }

    @Test("empty ItemType round-trips with empty properties + views")
    func emptyItemType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        let t = ItemType(id: "01H", title: "Empty", icon: nil, properties: [], views: [], modifiedAt: Date())
        try t.save(to: metaURL)
        let loaded = try ItemType.load(from: metaURL)
        #expect(loaded.properties == [])
        #expect(loaded.views == [])
        #expect(loaded.templateConfig == nil)
        #expect(loaded.collectionOrder == nil)
        #expect(loaded.itemOrder == nil)
    }

    @Test("ItemType equality holds across encode/decode")
    func equality() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Eq", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        let original = ItemType(
            id: "01HEQ", title: "Eq", icon: "tag",
            properties: [PropertyDefinition(name: "p", type: .number)],
            views: [], modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)
        let loaded = try ItemType.load(from: metaURL)
        #expect(loaded == original)
    }
}
