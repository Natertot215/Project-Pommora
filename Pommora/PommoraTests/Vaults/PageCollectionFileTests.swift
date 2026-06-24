import Foundation
import Testing

@testable import Pommora

@Suite("PageCollectionFile")
struct PageCollectionFileTests {

    @Test("PageCollection round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Planner", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

        let original = PageCollection(
            id: "01HVAULT",
            title: "Planner",
            icon: "folder",
            properties: [
                PropertyDefinition(
                    id: "", name: "status",
                    type: .select,
                    selectOptions: [
                        PropertyDefinition.SelectOption(value: "active", label: "Active", color: .green),
                        PropertyDefinition.SelectOption(value: "done", label: "Done", color: .gray),
                    ]
                ),
                PropertyDefinition(id: "", name: "due", type: .date, dateIncludesTime: false),
            ],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.id == "01HVAULT")
        #expect(loaded.title == "Planner")
        #expect(loaded.icon == "folder")
        #expect(loaded.properties.count == 2)
        #expect(loaded.properties[0].name == "status")
        #expect(loaded.properties[0].type == .select)
    }

    @Test("PageCollection on-disk JSON omits title")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Materials", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

        try PageCollection(id: "01H", title: "Materials", icon: nil, properties: [], views: [], modifiedAt: Date())
            .save(to: metaURL)
        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("PageCollection `open_in` round-trips; absent key decodes to nil")
    func openInRoundTrip() throws {
        // Legacy sidecar (no openIn): the key is never written and decodes nil.
        let legacy = PageCollection(
            id: "01H", title: "T", icon: nil, properties: [], views: [],
            modifiedAt: Date(timeIntervalSince1970: 0))
        let legacyData = try JSONEncoder().encode(legacy)
        let legacyJSON = try JSONSerialization.jsonObject(with: legacyData) as? [String: Any]
        #expect(legacyJSON?["open_in"] == nil)
        #expect(try JSONDecoder().decode(PageCollection.self, from: legacyData).openIn == nil)

        // Each mode writes its raw value and round-trips.
        for (mode, raw) in [(OpenInMode.compact, "compact"), (OpenInMode.window, "window")] {
            var t = legacy
            t.openIn = mode
            let data = try JSONEncoder().encode(t)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["open_in"] as? String == raw)
            #expect(try JSONDecoder().decode(PageCollection.self, from: data).openIn == mode)
        }
    }

    @Test("empty PageCollection round-trips with empty properties + views")
    func emptyPageCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

        let v = PageCollection(id: "01H", title: "Empty", icon: nil, properties: [], views: [], modifiedAt: Date())
        try v.save(to: metaURL)
        let loaded = try PageCollection.load(from: metaURL)
        #expect(loaded.properties == [])
        #expect(loaded.views == [])
    }
}
