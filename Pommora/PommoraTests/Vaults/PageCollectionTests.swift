import Foundation
import Testing

@testable import Pommora

@Suite("PageCollectionFile")
struct PageCollectionTests {

    @Test("PageSet round-trips through _pagecollection.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Planner", isDirectory: true)
            .appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        let original = PageSet(
            id: "01HCOLL",
            parentID: "01HVAULT",
            title: "Tasks",
            folderURL: folder,
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.id == "01HCOLL")
        #expect(loaded.parentID == "01HVAULT")
        #expect(loaded.title == "Tasks")
        #expect(loaded.folderURL == folder)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("PageSet on-disk JSON uses snake_case for parent_id + modified_at")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HV", title: "C",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"parent_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(!raw.contains("\"parentID\""))
        #expect(!raw.contains("\"title\""))  // title not persisted
        #expect(!raw.contains("\"folderURL\""))  // folderURL not persisted
    }

    @Test("PageSet title derives from parent folder name on load")
    func titleFromFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("Side Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HV", title: "Side Projects",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.title == "Side Projects")
    }

    @Test("PageSet folderURL derives from metadata URL parent on load")
    func folderURLDerived() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HV", title: "X",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.folderURL == folder)
    }

    @Test("PageSet set_order round-trips and is omitted when nil")
    func setOrderRoundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)

        try PageSet(
            id: "01H", parentID: "01HV", title: "C",
            folderURL: folder, modifiedAt: Date(),
            setOrder: ["01HSET1", "01HSET2"]
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"set_order\""))

        let loaded = try PageSet.load(from: metaURL)
        #expect(loaded.setOrder == ["01HSET1", "01HSET2"])

        try PageSet(
            id: "01H", parentID: "01HV", title: "C",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)
        let rawNil = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!rawNil.contains("\"set_order\""))
        #expect(try PageSet.load(from: metaURL).setOrder == nil)
    }
}
