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

    // MARK: - ParadigmV2 wrapper folders

    @Test("pagesWrapperDir is rootURL/Pages")
    func pagesWrapperDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.pagesWrapperDir(in: nexus)
        #expect(dir.lastPathComponent == "Pages")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
        // URL-form overload matches the Nexus-typed form
        #expect(NexusPaths.pagesWrapperDir(in: nexus.rootURL) == dir)
    }

    @Test("itemsWrapperDir is rootURL/Items")
    func itemsWrapperDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.itemsWrapperDir(in: nexus.rootURL)
        #expect(dir.lastPathComponent == "Items")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("agendaWrapperDir is rootURL/Agenda")
    func agendaWrapperDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.agendaWrapperDir(in: nexus)
        #expect(dir.lastPathComponent == "Agenda")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
        // URL-form overload matches the Nexus-typed form
        #expect(NexusPaths.agendaWrapperDir(in: nexus.rootURL) == dir)
    }

    @Test("reservedTopLevelFolderNames contains Pages, Items, and Agenda")
    func reservedTopLevelFolderNames() throws {
        let reserved = NexusPaths.reservedTopLevelFolderNames
        #expect(reserved.contains("Pages"))
        #expect(reserved.contains("Items"))
        #expect(reserved.contains("Agenda"))
        #expect(reserved.count == 3)
    }

    @Test("tasksDir is Agenda/Tasks; eventsDir is Agenda/Events")
    func tasksAndEventsDirsShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let tasks = NexusPaths.tasksDir(in: nexus)
        let events = NexusPaths.eventsDir(in: nexus)
        #expect(tasks.lastPathComponent == "Tasks")
        #expect(tasks.deletingLastPathComponent().lastPathComponent == "Agenda")
        #expect(events.lastPathComponent == "Events")
        #expect(events.deletingLastPathComponent().lastPathComponent == "Agenda")
    }

    @Test("named file URLs use the documented extensions")
    func namedFileExtensions() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(NexusPaths.tierConfigURL(in: nexus).lastPathComponent == "tier-config.json")
        #expect(NexusPaths.savedConfigURL(in: nexus).lastPathComponent == "saved-config.json")
        #expect(NexusPaths.homepageURL(in: nexus).lastPathComponent == "homepage.json")
        #expect(
            NexusPaths.taskSchemaURL(in: nexus).lastPathComponent
                == NexusPaths.schemaSidecarFilename
        )
        #expect(
            NexusPaths.eventSchemaURL(in: nexus).lastPathComponent
                == NexusPaths.schemaSidecarFilename
        )
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

    @Test("projectFileURL nests inside parent Topic folder with .project.json")
    func projectFileFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.projectFileURL(
            forTitle: "GTD method",
            inTopicTitled: "Productivity",
            in: nexus
        )
        #expect(url.lastPathComponent == "GTD method.project.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Productivity")
    }

    // MARK: - PageType / PageCollection (flatlayout: rooted at the nexus root)

    @Test("pageTypeFolderURL sits at the nexus root (no wrapper)")
    func pageTypeFolderShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Recipes"
        )
        #expect(folder.lastPathComponent == "Recipes")
        #expect(folder.deletingLastPathComponent().path == nexus.rootURL.path)

        // metadata URL co-located using the per-kind PageType sidecar
        let meta = NexusPaths.pageTypeMetadataURL(
            in: nexus.rootURL, typeFolderName: "Recipes"
        )
        #expect(meta.lastPathComponent == NexusPaths.pageTypeSidecarFilename)
        #expect(meta.deletingLastPathComponent() == folder)
    }

    @Test("pageCollectionFolderURL nests inside <Type>/<Collection> at root")
    func pageCollectionFolderShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.pageCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Recipes",
            collectionFolderName: "Dinners"
        )
        #expect(folder.lastPathComponent == "Dinners")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Recipes")
        #expect(
            folder.deletingLastPathComponent().deletingLastPathComponent().path == nexus.rootURL.path
        )

        // metadata sidecar uses the per-kind PageCollection name
        let meta = NexusPaths.pageCollectionMetadataURL(
            in: nexus.rootURL,
            typeFolderName: "Recipes",
            collectionFolderName: "Dinners"
        )
        #expect(meta.lastPathComponent == NexusPaths.pageCollectionSidecarFilename)
        #expect(meta.deletingLastPathComponent() == folder)
    }

    @Test("legacy vaultFolderURL / vaultMetadataURL aliases route to the flat layout")
    func legacyVaultAliasesRootAtNexus() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.vaultFolderURL(forTitle: "Planner", in: nexus)
        #expect(folder.lastPathComponent == "Planner")
        #expect(folder.deletingLastPathComponent().path == nexus.rootURL.path)
        let meta = NexusPaths.vaultMetadataURL(forTitle: "Planner", in: nexus)
        #expect(meta.lastPathComponent == NexusPaths.pageTypeSidecarFilename)
        #expect(meta.deletingLastPathComponent() == folder)
    }

    @Test("legacy collectionFolderURL nests inside <Vault>/<Collection> at root")
    func legacyCollectionAliasRootsAtNexus() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.collectionFolderURL(
            forTitle: "Tasks",
            inVaultTitled: "Planner",
            in: nexus
        )
        #expect(url.lastPathComponent == "Tasks")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Planner")
        #expect(
            url.deletingLastPathComponent().deletingLastPathComponent().path == nexus.rootURL.path
        )
    }

    // MARK: - ItemType / ItemCollection (rooted at <nexus>/Items/)

    @Test("itemTypeFolderURL nests inside Items/ wrapper")
    func itemTypeFolderShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        #expect(folder.lastPathComponent == "Errands")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Items")
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent().path == nexus.rootURL.path)

        let meta = NexusPaths.itemTypeMetadataURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        #expect(meta.lastPathComponent == NexusPaths.schemaSidecarFilename)
        #expect(meta.deletingLastPathComponent() == folder)
    }

    @Test("itemCollectionFolderURL nests inside <Items>/<Type>/<Collection>")
    func itemCollectionFolderShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: "Errands",
            collectionFolderName: "Groceries"
        )
        #expect(folder.lastPathComponent == "Groceries")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Errands")
        #expect(
            folder.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Items"
        )

        let meta = NexusPaths.itemCollectionMetadataURL(
            in: nexus.rootURL,
            typeFolderName: "Errands",
            collectionFolderName: "Groceries"
        )
        #expect(meta.lastPathComponent == NexusPaths.schemaSidecarFilename)
        #expect(meta.deletingLastPathComponent() == folder)
    }

    @Test("pageFileURL + itemFileURL use the right extensions inside a PageCollection")
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

    @Test("taskFileURL nests inside Agenda/Tasks with .task.json extension")
    func taskFilePath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.taskFileURL(forTitle: "Submit grant proposal", in: nexus)
        #expect(url.lastPathComponent == "Submit grant proposal.task.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Tasks")
        #expect(
            url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Agenda"
        )
    }

    @Test("eventFileURL nests inside Agenda/Events with .event.json extension")
    func eventFilePath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.eventFileURL(forTitle: "Team standup", in: nexus)
        #expect(url.lastPathComponent == "Team standup.event.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Events")
        #expect(
            url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Agenda"
        )
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
