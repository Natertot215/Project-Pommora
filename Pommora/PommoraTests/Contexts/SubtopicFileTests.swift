import Foundation
import Testing
@testable import Pommora

@Suite("SubtopicFile")
struct SubtopicFileTests {

    @Test("Subtopic round-trips; title derives from filename")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("GTD method.subtopic.json")

        let original = Subtopic(
            id: "01HSUB",
            title: "GTD method",
            parents: ["01HTOPIC-PRODUCTIVITY"],
            linkedRelations: ["01HTOPIC-OTHER", "01HSPACE-PERSONAL"],
            icon: "checklist",
            blocks: [],
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )
        try original.save(to: url)

        let loaded = try Subtopic.load(from: url)
        #expect(loaded.id == "01HSUB")
        #expect(loaded.title == "GTD method")
        #expect(loaded.parents == ["01HTOPIC-PRODUCTIVITY"])
        #expect(loaded.linkedRelations == ["01HTOPIC-OTHER", "01HSPACE-PERSONAL"])
        #expect(loaded.icon == "checklist")
        #expect(loaded.tier == 3)
    }

    @Test("Subtopic on-disk JSON omits title field")
    func titleNotPersisted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/Productivity", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Foo.subtopic.json")

        let st = Subtopic(
            id: "01H",
            title: "Foo",
            parents: ["01HPARENT"],
            linkedRelations: [],
            icon: nil,
            blocks: [],
            modifiedAt: Date()
        )
        try st.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"title\""))
    }

    @Test("Subtopic uses snake_case linked_relations on disk")
    func linkedRelationsKey() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL
            .appendingPathComponent(".nexus/topics/X", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Y.subtopic.json")

        let st = Subtopic(
            id: "01H", title: "Y", parents: ["01HP"],
            linkedRelations: ["01HZ"], icon: nil, blocks: [], modifiedAt: Date()
        )
        try st.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"linked_relations\""))
        #expect(!raw.contains("\"linkedRelations\""))
    }
}
