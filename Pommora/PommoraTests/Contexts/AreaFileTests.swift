import Foundation
import Testing

@testable import Pommora

@Suite("AreaFile")
struct AreaFileTests {

    @Test("Area round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.areaFolderURL(forTitle: "Personal", in: nexus),
            withIntermediateDirectories: true)

        let original = Area(
            id: "01HX2K6Z3V4Y5W6X7Y8Z9A0B1C",
            title: "Personal",
            icon: "person.circle",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        var loaded = try Area.load(from: url)
        // title is derived from folder name on load — overwrite to match
        loaded.title = "Personal"
        #expect(loaded == original)
    }

    @Test("Area on-disk JSON omits title field (filename = title rule)")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.areaMetadataURL(forTitle: "Work", in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.areaFolderURL(forTitle: "Work", in: nexus),
            withIntermediateDirectories: true)

        let area = Area(
            id: "01HX",
            title: "Work",
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try area.save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""), "title field must not appear on disk")
    }

    @Test("Area tier is always 1 after load")
    func tierAlways1() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.areaMetadataURL(forTitle: "Academics", in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.areaFolderURL(forTitle: "Academics", in: nexus),
            withIntermediateDirectories: true)

        let area = Area(
            id: "01H",
            title: "Academics",
            icon: "book.closed",
            blocks: [],
            modifiedAt: Date()
        )
        try area.save(to: url)
        let loaded = try Area.load(from: url)
        #expect(loaded.tier == 1)
    }

    @Test("Area load derives title from folder name")
    func titleFromFolderName() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.areaMetadataURL(forTitle: "Side Projects", in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.areaFolderURL(forTitle: "Side Projects", in: nexus),
            withIntermediateDirectories: true)

        let area = Area(
            id: "01H",
            title: "Side Projects",
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try area.save(to: url)
        let loaded = try Area.load(from: url)
        #expect(loaded.title == "Side Projects")
    }
}
