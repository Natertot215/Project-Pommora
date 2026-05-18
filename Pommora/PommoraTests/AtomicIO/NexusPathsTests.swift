import Foundation
import Testing

@testable import Pommora

@Suite("NexusPaths")
struct NexusPathsTests {

    @Test("nexusConfigDir is rootURL/.nexus")
    func nexusConfigDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.nexusConfigDir(in: nexus)
        #expect(dir.lastPathComponent == ".nexus")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("spacesDir is .nexus/spaces")
    func spacesDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.spacesDir(in: nexus)
        #expect(dir.lastPathComponent == "spaces")
        #expect(dir.deletingLastPathComponent().lastPathComponent == ".nexus")
    }

    @Test("topicsDir is .nexus/topics")
    func topicsDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.topicsDir(in: nexus)
        #expect(dir.lastPathComponent == "topics")
        #expect(dir.deletingLastPathComponent().lastPathComponent == ".nexus")
    }

    @Test("agendaDir is rootURL/Agenda")
    func agendaDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.agendaDir(in: nexus)
        #expect(dir.lastPathComponent == "Agenda")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("named file URLs use the documented extensions")
    func namedFileExtensions() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(NexusPaths.tierConfigURL(in: nexus).lastPathComponent == "tier-config.json")
        #expect(NexusPaths.savedConfigURL(in: nexus).lastPathComponent == "saved-config.json")
        #expect(NexusPaths.homepageURL(in: nexus).lastPathComponent == "homepage.json")
        #expect(NexusPaths.agendaSchemaURL(in: nexus).lastPathComponent == "_agenda.json")
    }

    @Test("spaceFileURL embeds title with .space.json extension")
    func spaceFileURLFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        #expect(url.lastPathComponent == "Personal.space.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "spaces")
    }

    @Test("topicFolderURL uses title as folder name; metadata file is _topic.json")
    func topicFolderFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.topicFolderURL(forTitle: "Productivity", in: nexus)
        #expect(folder.lastPathComponent == "Productivity")
        let meta = NexusPaths.topicMetadataURL(forTitle: "Productivity", in: nexus)
        #expect(meta.lastPathComponent == "_topic.json")
        #expect(meta.deletingLastPathComponent().lastPathComponent == "Productivity")
    }

    @Test("subtopicFileURL nests inside parent Topic folder with .subtopic.json")
    func subtopicFileFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.subtopicFileURL(
            forTitle: "GTD method",
            inTopicTitled: "Productivity",
            in: nexus
        )
        #expect(url.lastPathComponent == "GTD method.subtopic.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Productivity")
    }

    @Test("vaultFolderURL is rootURL/<title>; metadata is _vault.json")
    func vaultPaths() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        #expect(folder.lastPathComponent == "Planner")
        #expect(folder.deletingLastPathComponent().path == nexus.rootURL.path)
        let meta = NexusPaths.vaultMetadataURL(forTitle: "Planner", in: nexus)
        #expect(meta.lastPathComponent == "_vault.json")
    }

    @Test("collectionFolderURL nests inside vault folder")
    func collectionPath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.collectionFolderURL(
            forTitle: "Tasks",
            inVaultTitled: "Planner",
            in: nexus
        )
        #expect(url.lastPathComponent == "Tasks")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Planner")
    }

    @Test("pageFileURL + itemFileURL use the right extensions inside a Collection")
    func contentFilePaths() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let collection = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        let page = NexusPaths.pageFileURL(forTitle: "Notes", in: collection)
        #expect(page.lastPathComponent == "Notes.md")
        let item = NexusPaths.itemFileURL(forTitle: "Buy groceries", in: collection)
        #expect(item.lastPathComponent == "Buy groceries.json")
    }

    @Test("agendaItemFileURL uses .agenda.json extension")
    func agendaItemPath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.agendaItemFileURL(forTitle: "Team standup", in: nexus)
        #expect(url.lastPathComponent == "Team standup.agenda.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Agenda")
    }

    @Test("ensureDirectoryExists creates intermediate dirs idempotently")
    func ensureDirectory() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let deep = nexus.rootURL
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c", isDirectory: true)
        try NexusPaths.ensureDirectoryExists(deep)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: deep.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        // Idempotent
        try NexusPaths.ensureDirectoryExists(deep)
    }
}
