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
            icon: "lightbulb",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.id == "01HABC")
        #expect(loaded.title == "Productivity")  // from folder
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

        let topic = Topic(id: "01H", title: "GTD", icon: nil, blocks: [], modifiedAt: Date())
        try topic.save(to: metaURL)
        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.tier == 2)
    }

    @Test("Legacy 'parents' key in JSON is silently ignored on decode; absent on encode")
    func parentsKeyIgnored() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent("_topic.json")

        // Write JSON that includes a legacy parents array.
        let legacy = """
            {"id":"01HLEG","tier":2,"parents":["01HSPACE-1"],"blocks":[],"modified_at":"2026-01-01T00:00:00.000Z"}
            """
        try legacy.write(to: metaURL, atomically: true, encoding: .utf8)

        // Decode must succeed (parents silently ignored).
        let loaded = try Topic.load(from: metaURL)
        #expect(loaded.id == "01HLEG")

        // Re-encode must NOT contain a parents key.
        try loaded.save(to: metaURL)
        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"parents\""))
    }
}
