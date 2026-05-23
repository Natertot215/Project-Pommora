import Foundation
import Testing

@testable import Pommora

@Suite("PageTypeFile")
struct PageTypeFileTests {

    @Test("PageType round-trips through AtomicJSON")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Planner", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

        let original = PageType(
            id: "01HVAULT",
            title: "Planner",
            icon: "folder",
            properties: [
                PropertyDefinition(
                    name: "status",
                    type: .select,
                    selectOptions: [
                        PropertyDefinition.SelectOption(value: "active", label: "Active", color: .green),
                        PropertyDefinition.SelectOption(value: "done", label: "Done", color: .gray),
                    ]
                ),
                PropertyDefinition(name: "due", type: .date, dateIncludesTime: false),
            ],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: metaURL)

        let loaded = try PageType.load(from: metaURL)
        #expect(loaded.id == "01HVAULT")
        #expect(loaded.title == "Planner")
        #expect(loaded.icon == "folder")
        #expect(loaded.properties.count == 2)
        #expect(loaded.properties[0].name == "status")
        #expect(loaded.properties[0].type == .select)
    }

    @Test("PageType on-disk JSON omits title")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Materials", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

        try PageType(id: "01H", title: "Materials", icon: nil, properties: [], views: [], modifiedAt: Date())
            .save(to: metaURL)
        let raw = try String(contentsOf: metaURL, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("empty PageType round-trips with empty properties + views")
    func emptyPageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)

        let v = PageType(id: "01H", title: "Empty", icon: nil, properties: [], views: [], modifiedAt: Date())
        try v.save(to: metaURL)
        let loaded = try PageType.load(from: metaURL)
        #expect(loaded.properties == [])
        #expect(loaded.views == [])
    }
}
