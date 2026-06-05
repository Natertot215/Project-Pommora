import Foundation
import Testing

@testable import Pommora

@Suite("ProjectFile")
struct ProjectFileTests {

    @Test("Project round-trips; title derives from filename")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("GTD method.project.json")

        let original = Project(
            id: "01HPROJ",
            title: "GTD method",
            parents: ["01HTOPIC-PRODUCTIVITY"],
            projectLinks: ["01HTOPIC-OTHER", "01HSPACE-PERSONAL"],
            icon: "checklist",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Project.load(from: url)
        #expect(loaded.id == "01HPROJ")
        #expect(loaded.title == "GTD method")
        #expect(loaded.parents == ["01HTOPIC-PRODUCTIVITY"])
        #expect(loaded.projectLinks == ["01HTOPIC-OTHER", "01HSPACE-PERSONAL"])
        #expect(loaded.icon == "checklist")
        #expect(loaded.tier == 3)
    }

    @Test("Project on-disk JSON omits title field")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Foo.project.json")

        let p = Project(
            id: "01H",
            title: "Foo",
            parents: ["01HPARENT"],
            projectLinks: [],
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try p.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Project uses snake_case project_links on disk")
    func projectLinksKey() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Y.project.json")

        let p = Project(
            id: "01H", title: "Y", parents: ["01HP"],
            projectLinks: ["01HZ"], icon: nil, blocks: [], modifiedAt: Date()
        )
        try p.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"project_links\""))
        #expect(!raw.contains("\"linked_relations\""))
        #expect(!raw.contains("\"projectLinks\""))
    }

    @Test("Project decodes legacy linked_relations key")
    func legacyLinkedRelationsDecode() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Legacy.project.json")

        // Write a JSON with the OLD key "linked_relations" directly.
        let legacyJSON = """
            {"id":"01HLEG","tier":3,"parents":["01HP"],"linked_relations":["01HOLD"],"modified_at":"2026-01-01T00:00:00Z"}
            """
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try Project.load(from: url)
        #expect(loaded.projectLinks == ["01HOLD"])
    }
}
