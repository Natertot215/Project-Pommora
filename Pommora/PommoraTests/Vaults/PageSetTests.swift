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
            collectionID: "01HCOLL",
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
        #expect(loaded.collectionID == "01HCOLL")
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
            id: "01H", collectionID: "01HC", title: "S",
            folderURL: folder, modifiedAt: Date(),
            pageOrder: ["01HP"]
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"collection_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(raw.contains("\"schema_version\""))
        #expect(raw.contains("\"page_order\""))
        #expect(!raw.contains("\"collectionID\""))
        #expect(!raw.contains("\"title\""))  // title not persisted
        #expect(!raw.contains("\"folderURL\""))  // folderURL not persisted
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
            id: "01H", collectionID: "01HC", title: "Side Quests",
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
            id: "01H", collectionID: "01HC", title: "S",
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
            id: "01H", collectionID: "01HC", title: "S",
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
