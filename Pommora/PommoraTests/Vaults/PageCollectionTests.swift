import Foundation
import Testing

@testable import Pommora

@Suite("PageCollectionFile")
struct PageCollectionTests {

    @Test("PageCollection round-trips through _pagecollection.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Planner", isDirectory: true)
            .appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        let original = PageCollection(
            id: "01HCOLL",
            typeID: "01HVAULT",
            title: "Tasks",
            folderURL: folder,
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.id == "01HCOLL")
        #expect(loaded.typeID == "01HVAULT")
        #expect(loaded.title == "Tasks")
        #expect(loaded.folderURL == folder)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("PageCollection on-disk JSON uses snake_case for type_id + modified_at")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageCollection(
            id: "01H", typeID: "01HV", title: "C",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"type_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(!raw.contains("\"typeID\""))
        #expect(!raw.contains("\"title\""))  // title not persisted
        #expect(!raw.contains("\"folderURL\""))  // folderURL not persisted
    }

    @Test("PageCollection title derives from parent folder name on load")
    func titleFromFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("Side Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageCollection(
            id: "01H", typeID: "01HV", title: "Side Projects",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.title == "Side Projects")
    }

    @Test("PageCollection folderURL derives from metadata URL parent on load")
    func folderURLDerived() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageCollection(
            id: "01H", typeID: "01HV", title: "X",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.folderURL == folder)
    }

    // MARK: - folderOrder (F.1.c) — coexists with pageOrder

    @Test("PageCollection.folderOrder defaults to nil on a freshly-init'd Collection")
    func folderOrderNilByDefault() {
        let coll = PageCollection(
            id: "01H",
            typeID: "01HV",
            title: "X",
            folderURL: URL(fileURLWithPath: "/"),
            modifiedAt: Date()
        )
        #expect(coll.folderOrder == nil)
        #expect(coll.pageOrder == nil)
    }

    @Test("PageCollection.folderOrder round-trips through _pagecollection.json")
    func folderOrderRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        let original = PageCollection(
            id: "01H",
            typeID: "01HV",
            title: "X",
            folderURL: folder,
            modifiedAt: Date(),
            folderOrder: ["folder_a", "folder_b", "folder_c"]
        )
        try original.save(to: metaURL)

        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.folderOrder == ["folder_a", "folder_b", "folder_c"])
    }

    @Test("PageCollection.folderOrder serializes under snake_case `folder_order`")
    func folderOrderSnakeCase() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageCollection(
            id: "01H", typeID: "01HV", title: "X",
            folderURL: folder, modifiedAt: Date(),
            folderOrder: ["f1"]
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"folder_order\""))
        #expect(!raw.contains("\"folderOrder\""))
    }

    @Test("nil folderOrder is omitted from the JSON via encodeIfPresent")
    func folderOrderNilOmitted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageCollection(
            id: "01H", typeID: "01HV", title: "X",
            folderURL: folder, modifiedAt: Date()
            // folderOrder omitted — defaults to nil
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"folder_order\""))
    }

    @Test("legacy sidecar without folder_order decodes as nil (forward-compat)")
    func folderOrderLegacyDecode() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        // Hand-written legacy JSON lacking folder_order — must decode cleanly.
        let legacyJSON = """
            {
              "id": "01HLEGACY",
              "type_id": "01HVAULT",
              "modified_at": "2025-01-01T00:00:00Z"
            }
            """
        try legacyJSON.write(to: metaURL, atomically: true, encoding: .utf8)
        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.folderOrder == nil)
        #expect(loaded.id == "01HLEGACY")
    }
}
