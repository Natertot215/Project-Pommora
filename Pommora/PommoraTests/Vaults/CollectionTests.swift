import Foundation
import Testing

@testable import Pommora

@Suite("CollectionFile")
struct CollectionTests {

    @Test("Collection round-trips through _schema.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Planner", isDirectory: true)
            .appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        let original = Collection(
            id: "01HCOLL",
            vaultID: "01HVAULT",
            title: "Tasks",
            folderURL: folder,
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try Collection.load(from: metaURL)
        #expect(loaded.id == "01HCOLL")
        #expect(loaded.vaultID == "01HVAULT")
        #expect(loaded.title == "Tasks")
        #expect(loaded.folderURL == folder)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("Collection on-disk JSON uses snake_case for vault_id + modified_at")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try Collection(
            id: "01H", vaultID: "01HV", title: "C",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"vault_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(!raw.contains("\"vaultID\""))
        #expect(!raw.contains("\"title\""))  // title not persisted
        #expect(!raw.contains("\"folderURL\""))  // folderURL not persisted
    }

    @Test("Collection title derives from parent folder name on load")
    func titleFromFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("Side Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try Collection(
            id: "01H", vaultID: "01HV", title: "Side Projects",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try Collection.load(from: metaURL)
        #expect(loaded.title == "Side Projects")
    }

    @Test("Collection folderURL derives from metadata URL parent on load")
    func folderURLDerived() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)

        try Collection(
            id: "01H", vaultID: "01HV", title: "X",
            folderURL: folder, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try Collection.load(from: metaURL)
        #expect(loaded.folderURL == folder)
    }
}
