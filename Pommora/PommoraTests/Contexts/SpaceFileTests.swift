import Foundation
import Testing
@testable import Pommora

@Suite("SpaceFile")
struct SpaceFileTests {

    @Test("Space round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Personal.space.json")

        let original = Space(
            id: "01HX2K6Z3V4Y5W6X7Y8Z9A0B1C",
            title: "Personal",
            color: .blue,
            icon: "person.circle",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        var loaded = try Space.load(from: url)
        // title is derived from filename on load — overwrite to match
        loaded.title = "Personal"
        #expect(loaded == original)
    }

    @Test("Space on-disk JSON omits title field (filename = title rule)")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Work.space.json")

        let space = Space(
            id: "01HX",
            title: "Work",
            color: .green,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try space.save(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""), "title field must not appear on disk")
    }

    @Test("Space tier is always 1 after load")
    func tierAlways1() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Academics.space.json")

        let space = Space(
            id: "01H",
            title: "Academics",
            color: .red,
            icon: "book.closed",
            blocks: [],
            modifiedAt: Date()
        )
        try space.save(to: url)
        let loaded = try Space.load(from: url)
        #expect(loaded.tier == 1)
    }

    @Test("Space load derives title from filename")
    func titleFromFilename() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = nexus.rootURL.appendingPathComponent("Side Projects.space.json")

        let space = Space(
            id: "01H",
            title: "Side Projects",
            color: .purple,
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try space.save(to: url)
        let loaded = try Space.load(from: url)
        #expect(loaded.title == "Side Projects")
    }
}
