import Foundation
import Testing

@testable import Pommora

@Suite("PageCollectionFile")
struct PageCollectionTests {

    @Test("PageCollection round-trips through _schema.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Planner", isDirectory: true)
            .appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

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
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

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
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

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
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try PageCollection(
            id: "01H", typeID: "01HV", title: "X",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.folderURL == folder)
    }
}
