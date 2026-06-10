import Foundation
import Testing

@testable import Pommora

@Suite("ProjectFile")
struct ProjectFileTests {

    @Test("Project round-trips; title derives from parent folder name")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/projects/GTD method", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("_project.json")

        let original = Project(
            id: "01HPROJ",
            title: "GTD method",
            icon: "checklist",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Project.load(from: url)
        #expect(loaded.id == "01HPROJ")
        #expect(loaded.title == "GTD method")  // from folder
        #expect(loaded.icon == "checklist")
        #expect(loaded.tier == 3)
        #expect(loaded.modifiedAt == Date(timeIntervalSince1970: 1716480000))
    }

    @Test("Project on-disk JSON omits title + containment keys")
    func bareSchemaOnDisk() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/projects/Foo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("_project.json")

        let p = Project(
            id: "01H",
            title: "Foo",
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try p.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
        #expect(!raw.contains("\"parents\""))
        #expect(!raw.contains("\"project_links\""))
        #expect(!raw.contains("\"linked_relations\""))
    }

    @Test("Project ignores legacy parents / project_links / linked_relations on decode")
    func legacyKeysIgnoredOnDecode() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/projects/Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("_project.json")

        // A legacy file carrying the now-dropped containment keys must still
        // decode — the keys are simply ignored.
        let legacyJSON = """
            {"id":"01HLEG","tier":3,"parents":["01HP"],"project_links":["01HZ"],"linked_relations":["01HOLD"],"icon":"star","modified_at":"2026-01-01T00:00:00Z"}
            """
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try Project.load(from: url)
        #expect(loaded.id == "01HLEG")
        #expect(loaded.title == "Legacy")
        #expect(loaded.icon == "star")
        #expect(loaded.tier == 3)
    }
}
