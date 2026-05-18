import Foundation
import Testing

@testable import Pommora

@Suite("TopicFile")
struct TopicFileTests {

    @Test("Topic round-trips through AtomicJSON; title derives from parent folder")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let original = Topic(
            id: "01HABC",
            title: "Productivity",
            parents: ["01HSPACE-PERSONAL", "01HSPACE-WORK"],
            icon: "lightbulb",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.id == "01HABC")
        #expect(loaded.title == "Productivity")  // from folder
        #expect(loaded.parents == ["01HSPACE-PERSONAL", "01HSPACE-WORK"])
        #expect(loaded.icon == "lightbulb")
        #expect(loaded.tier == 2)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("Topic on-disk JSON omits title field")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/CS-161", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let topic = Topic(
            id: "01H",
            title: "CS-161",
            parents: ["01HSPACE-ACADEMICS"],
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try topic.save(to: metaURL)

        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Topic tier is always 2 after load")
    func tierAlways2() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/GTD", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let topic = Topic(id: "01H", title: "GTD", parents: [], icon: nil, blocks: [], modifiedAt: Date())
        try topic.save(to: metaURL)
        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.tier == 2)
    }

    @Test("Topic supports zero parents (Space-less topic allowed)")
    func zeroParents() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Loose", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        let topic = Topic(id: "01H", title: "Loose", parents: [], icon: nil, blocks: [], modifiedAt: Date())
        try topic.save(to: metaURL)
        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.parents == [])
    }
}
