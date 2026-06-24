import Foundation
import Testing

@testable import Pommora

@Suite("PageSetCodableTests")
struct PageSetTests {

    @Test("PageSet round-trips every persisted field through _pageset.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Planner", isDirectory: true)
            .appendingPathComponent("Tasks", isDirectory: true)
            .appendingPathComponent("Weekly", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)

        let original = PageSet(
            id: "01HSET",
            parentID: "01HCOLL",
            title: "Weekly",
            folderURL: folder,
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            schemaVersion: 1,
            icon: "tray.full",
            pageOrder: ["01HPAGE1", "01HPAGE2"]
        )
        try original.save(to: metaURL)

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.id == "01HSET")
        #expect(loaded.parentID == "01HCOLL")
        #expect(loaded.title == "Weekly")
        #expect(loaded.folderURL == folder)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
        #expect(loaded.schemaVersion == 1)
        #expect(loaded.icon == "tray.full")
        #expect(loaded.pageOrder == ["01HPAGE1", "01HPAGE2"])
    }

    @Test("PageSet on-disk JSON uses snake_case and omits title + folderURL")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("S", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HC", title: "S",
            folderURL: folder, modifiedAt: Date(),
            pageOrder: ["01HP"]
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"parent_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(raw.contains("\"schema_version\""))
        #expect(raw.contains("\"page_order\""))
        #expect(!raw.contains("\"collection_id\""))
        #expect(!raw.contains("\"collectionID\""))
        #expect(!raw.contains("\"title\""))
        #expect(!raw.contains("\"folderURL\""))
    }

    @Test("PageSet title + folderURL derive from the sidecar's parent folder on load")
    func titleAndFolderURLDerived() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("Side Quests", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HC", title: "Side Quests",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.title == "Side Quests")
        #expect(loaded.folderURL == folder)
    }

    @Test("PageSet decoder sets title + folderURL placeholders before load(from:) overwrites")
    func decoderPlaceholders() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("S", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HC", title: "S",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let decoded = try AtomicJSON.decode(PageSet.self, from: metaURL)
        #expect(decoded.title == "")
        #expect(decoded.folderURL == URL(fileURLWithPath: "/"))
    }

    @Test("PageSet nil icon + nil pageOrder round-trip as nil and stay off disk")
    func nilOptionalsRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("S", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageSetSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HC", title: "S",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"icon\""))
        #expect(!raw.contains("\"page_order\""))

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.icon == nil)
        #expect(loaded.pageOrder == nil)
    }
}

@Suite("PageSetDecoderEraTests")
struct PageSetDecoderEraTests {

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test("Decode old _pagecollection.json shape (type_id + views + set_order) → parentID from type_id")
    func decodeOldPageCollectionShape() throws {
        let json = """
        {
          "id": "01HTYPE01",
          "type_id": "01HPARENT",
          "modified_at": "2024-05-01T00:00:00Z",
          "schema_version": 1,
          "views": [{}],
          "set_order": ["01HSET1", "01HSET2"]
        }
        """
        let set = try makeDecoder().decode(PageSet.self, from: Data(json.utf8))
        #expect(set.parentID == "01HPARENT")
        #expect(!set.views.isEmpty)
        #expect(set.setOrder == ["01HSET1", "01HSET2"])
    }

    @Test("Decode old _pageset.json shape (collection_id, no views key) → parentID from collection_id, views empty")
    func decodeOldPageSetShape() throws {
        let json = """
        {
          "id": "01HSET01",
          "collection_id": "01HCOLL",
          "modified_at": "2024-05-01T00:00:00Z",
          "schema_version": 1
        }
        """
        let set = try makeDecoder().decode(PageSet.self, from: Data(json.utf8))
        #expect(set.parentID == "01HCOLL")
        #expect(set.views == [])
    }

    @Test("Decode ParadigmV1 blob (vault_id, no parent_id/type_id/collection_id) → parentID from vault_id")
    func decodeParadigmV1Shape() throws {
        let json = """
        {
          "id": "01HV1SET",
          "vault_id": "01HVAULT",
          "modified_at": "2024-05-01T00:00:00Z",
          "schema_version": 0
        }
        """
        let set = try makeDecoder().decode(PageSet.self, from: Data(json.utf8))
        #expect(set.parentID == "01HVAULT")
    }

    @Test("Decode new blob (parent_id) → parentID from parent_id")
    func decodeNewShape() throws {
        let json = """
        {
          "id": "01HNEW01",
          "parent_id": "01HPARENT",
          "modified_at": "2024-05-01T00:00:00Z",
          "schema_version": 1
        }
        """
        let set = try makeDecoder().decode(PageSet.self, from: Data(json.utf8))
        #expect(set.parentID == "01HPARENT")
    }

    @Test("Round-trip: encode then decode, equal; encoded JSON has parent_id, no legacy keys")
    func roundTripEncodesParentID() throws {
        let original = PageSet(
            id: "01HRT01",
            parentID: "01HPAR01",
            title: "Roundtrip",
            folderURL: URL(fileURLWithPath: "/"),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            schemaVersion: 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"parent_id\""))
        #expect(!json.contains("\"vault_id\""))
        #expect(!json.contains("\"type_id\""))
        #expect(!json.contains("\"collection_id\""))

        let decoded = try makeDecoder().decode(PageSet.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.parentID == original.parentID)
        #expect(decoded.schemaVersion == original.schemaVersion)
    }

    @Test("Decode blob where parent_id is a number (not string) → throws, not silent fallthrough")
    func decodeMalformedParentIDThrows() throws {
        let json = """
        {
          "id": "01HBAD01",
          "parent_id": 42,
          "modified_at": "2024-05-01T00:00:00Z",
          "schema_version": 1
        }
        """
        #expect(throws: (any Error).self) {
            try makeDecoder().decode(PageSet.self, from: Data(json.utf8))
        }
    }

    @Test("Decode blob with none of the four parent keys → throws")
    func decodeNoParentKeyThrows() throws {
        let json = """
        {
          "id": "01HNOP01",
          "modified_at": "2024-05-01T00:00:00Z",
          "schema_version": 1
        }
        """
        #expect(throws: (any Error).self) {
            try makeDecoder().decode(PageSet.self, from: Data(json.utf8))
        }
    }
}
