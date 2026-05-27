import Foundation
import Testing

@testable import Pommora

/// Folder is the third-tier container on the Pages side (PageType →
/// PageCollection → Folder → Page; the three-layer maximum). Mirrors
/// PageCollection's shape with `collectionID` and `icon` added — Folders
/// have customizable per-folder icons (Collections do not).
@Suite("FolderFile")
struct FolderTests {

    @Test("Folder round-trips through _folder.json")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("Research", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("2026-Q2", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.folderSidecarFilename)

        let original = Folder(
            id: "01HFOLDER",
            typeID: "01HVAULT",
            collectionID: "01HCOLL",
            title: "2026-Q2",
            folderURL: folder,
            icon: "book.closed",
            modifiedAt: Date(timeIntervalSince1970: 1_716_480_000)
        )
        try original.save(to: metaURL)

        let loaded = try Folder.load(from: metaURL)
        #expect(loaded.id == "01HFOLDER")
        #expect(loaded.typeID == "01HVAULT")
        #expect(loaded.collectionID == "01HCOLL")
        #expect(loaded.title == "2026-Q2")
        #expect(loaded.folderURL == folder)
        #expect(loaded.icon == "book.closed")
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1_716_480_000))
    }

    @Test("Folder on-disk JSON uses snake_case for type_id + collection_id + modified_at")
    func snakeCaseKeys() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("F", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.folderSidecarFilename)

        try Folder(
            id: "01H",
            typeID: "01HV",
            collectionID: "01HC",
            title: "F",
            folderURL: folder,
            icon: nil,
            modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(raw.contains("\"type_id\""))
        #expect(raw.contains("\"collection_id\""))
        #expect(raw.contains("\"modified_at\""))
        #expect(raw.contains("\"schema_version\""))
        // CamelCase variants must not leak.
        #expect(!raw.contains("\"typeID\""))
        #expect(!raw.contains("\"collectionID\""))
        #expect(!raw.contains("\"modifiedAt\""))
    }

    @Test("icon is omitted when nil — encodeIfPresent")
    func nilIconOmitted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("F", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.folderSidecarFilename)

        try Folder(
            id: "01H", typeID: "01HV", collectionID: "01HC",
            title: "F", folderURL: folder, icon: nil, modifiedAt: Date()
        ).save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"icon\""))
    }

    @Test("schema_version defaults to 1 when init() omits it; legacy sidecars without it decode as 0")
    func schemaVersionDefaults() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("F", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.folderSidecarFilename)

        // Fresh init() → schemaVersion == 1
        let fresh = Folder(
            id: "01H", typeID: "01HV", collectionID: "01HC",
            title: "F", folderURL: folder, icon: nil, modifiedAt: Date()
        )
        #expect(fresh.schemaVersion == 1)

        // Hand-written JSON lacking schema_version → decodes as 0 (forward-compat).
        let legacyJSON = """
            {
              "id": "01HLEGACY",
              "type_id": "01HV",
              "collection_id": "01HC",
              "modified_at": "2025-01-01T00:00:00Z"
            }
            """
        try legacyJSON.write(to: metaURL, atomically: true, encoding: .utf8)
        let loaded = try Folder.load(from: metaURL)
        #expect(loaded.schemaVersion == 0)
        #expect(loaded.id == "01HLEGACY")
    }

    @Test("title is derived from folder name on load (not persisted)")
    func titleFromFolderName() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent("V", isDirectory: true)
            .appendingPathComponent("C", isDirectory: true)
            .appendingPathComponent("MyTopic", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.folderSidecarFilename)

        // Save with one title, then rename the folder on disk; load should
        // reflect the new folder name (filename-as-title rule).
        try Folder(
            id: "01H", typeID: "01HV", collectionID: "01HC",
            title: "OldName", folderURL: folder, icon: nil, modifiedAt: Date()
        ).save(to: metaURL)

        let loaded = try Folder.load(from: metaURL)
        #expect(loaded.title == "MyTopic")  // derived from parent folder name, not stored
    }
}
