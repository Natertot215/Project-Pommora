import Foundation
import Testing

@testable import Pommora

@Suite("NexusPaths")
struct NexusPathsTests {

    private func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath() }

    @Test("nexusConfigDir is rootURL/.nexus")
    func nexusConfigDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.nexusConfigDir(in: nexus)
        #expect(dir.lastPathComponent == ".nexus")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("areasDir is .nexus/areas")
    func areasDirShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.areasDir(in: nexus)
        #expect(dir.lastPathComponent == "areas")
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

    // MARK: - Per-kind sidecar filenames (flatlayout)

    @Test("per-kind sidecar filenames are stable + distinct")
    func perKindSidecarFilenames() {
        #expect(NexusPaths.pageTypeSidecarFilename == "_pagetype.json")
        #expect(NexusPaths.pageCollectionSidecarFilename == "_pagecollection.json")
        #expect(NexusPaths.taskConfigSidecarFilename == "_taskconfig.json")
        #expect(NexusPaths.eventConfigSidecarFilename == "_eventconfig.json")
        // All four should be distinct.
        let all: Set<String> = [
            NexusPaths.pageTypeSidecarFilename,
            NexusPaths.pageCollectionSidecarFilename,
            NexusPaths.taskConfigSidecarFilename,
            NexusPaths.eventConfigSidecarFilename,
        ]
        #expect(all.count == 4)
    }

    // MARK: - Agenda singleton discovery (sidecar-driven)

    @Test("tasksDir falls back to <nexus>/Tasks when no _taskconfig.json exists")
    func tasksDirDefaultFallback() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.tasksDir(in: nexus)
        #expect(dir.lastPathComponent == "Tasks")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("eventsDir falls back to <nexus>/Events when no _eventconfig.json exists")
    func eventsDirDefaultFallback() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let dir = NexusPaths.eventsDir(in: nexus)
        #expect(dir.lastPathComponent == "Events")
        #expect(dir.deletingLastPathComponent().path == nexus.rootURL.path)
    }

    @Test("tasksDir discovers a renamed folder by _taskconfig.json presence")
    func tasksDirDiscoversRenamedFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Simulate a user-renamed Tasks singleton ("Errands/" carrying _taskconfig.json).
        let renamed = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: renamed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(
            to: renamed.appendingPathComponent(NexusPaths.taskConfigSidecarFilename)
        )

        let resolved = NexusPaths.tasksDir(in: nexus)
        #expect(resolved.lastPathComponent == "Errands")
        #expect(canonical(resolved).path == canonical(renamed).path)
    }

    @Test("eventsDir discovers a renamed folder by _eventconfig.json presence")
    func eventsDirDiscoversRenamedFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let renamed = nexus.rootURL.appendingPathComponent("Calendar", isDirectory: true)
        try FileManager.default.createDirectory(at: renamed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(
            to: renamed.appendingPathComponent(NexusPaths.eventConfigSidecarFilename)
        )

        let resolved = NexusPaths.eventsDir(in: nexus)
        #expect(resolved.lastPathComponent == "Calendar")
        #expect(canonical(resolved).path == canonical(renamed).path)
    }

    @Test("tasksDir picks first-found when multiple folders carry _taskconfig.json")
    func tasksDirFirstFoundOnPathologicalDuplicates() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Two folders both carrying _taskconfig.json — pathological case per
        // locked decision #5. First-found wins; warning logged to stderr.
        for name in ["AlphaTasks", "BetaTasks"] {
            let folder = nexus.rootURL.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{}".utf8).write(
                to: folder.appendingPathComponent(NexusPaths.taskConfigSidecarFilename)
            )
        }
        let resolved = NexusPaths.tasksDir(in: nexus)
        let candidates = Set(["AlphaTasks", "BetaTasks"])
        #expect(candidates.contains(resolved.lastPathComponent))
        #expect(canonical(resolved.deletingLastPathComponent()).path == canonical(nexus.rootURL).path)
    }

    @Test("taskSchemaURL / eventSchemaURL use per-kind sidecar filenames")
    func agendaSchemaURLsUsePerKindSidecars() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(
            NexusPaths.taskSchemaURL(in: nexus).lastPathComponent
                == NexusPaths.taskConfigSidecarFilename
        )
        #expect(
            NexusPaths.eventSchemaURL(in: nexus).lastPathComponent
                == NexusPaths.eventConfigSidecarFilename
        )
        // Default-fallback parents
        #expect(
            NexusPaths.taskSchemaURL(in: nexus).deletingLastPathComponent().lastPathComponent
                == "Tasks"
        )
        #expect(
            NexusPaths.eventSchemaURL(in: nexus).deletingLastPathComponent().lastPathComponent
                == "Events"
        )
    }

    @Test("named file URLs use the documented extensions")
    func namedFileExtensions() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        #expect(NexusPaths.tierConfigURL(in: nexus).lastPathComponent == "tier-config.json")
        #expect(NexusPaths.savedConfigURL(in: nexus).lastPathComponent == "saved-config.json")
        #expect(NexusPaths.homepageURL(in: nexus).lastPathComponent == "homepage.json")
    }

    @Test("areaFolderURL uses title as folder name under areas/; areaMetadataURL appends _area.json")
    func areaFolderURLFormat() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.areaFolderURL(forTitle: "Personal", in: nexus)
        #expect(folder.lastPathComponent == "Personal")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "areas")
        let meta = NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus)
        #expect(meta.lastPathComponent == "_area.json")
        #expect(meta.deletingLastPathComponent().lastPathComponent == "Personal")
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

    @Test("pageFileURL uses the .md extension inside a PageCollection")
    func contentFilePaths() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let collection = NexusPaths.collectionFolderURL(
            forTitle: "Tasks", inVaultTitled: "Planner", in: nexus
        )
        let page = NexusPaths.pageFileURL(forTitle: "Notes", in: collection)
        #expect(page.lastPathComponent == "Notes.md")
    }

    @Test("taskFileURL nests inside the Tasks singleton with .task.json extension")
    func taskFilePath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.taskFileURL(forTitle: "Submit grant proposal", in: nexus)
        #expect(url.lastPathComponent == "Submit grant proposal.task.json")
        // Default-name fallback: parent is <nexus>/Tasks/, no Agenda wrapper.
        #expect(url.deletingLastPathComponent().lastPathComponent == "Tasks")
        #expect(
            url.deletingLastPathComponent().deletingLastPathComponent().path == nexus.rootURL.path
        )
    }

    @Test("eventFileURL nests inside the Events singleton with .event.json extension")
    func eventFilePath() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let url = NexusPaths.eventFileURL(forTitle: "Team standup", in: nexus)
        #expect(url.lastPathComponent == "Team standup.event.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Events")
        #expect(
            url.deletingLastPathComponent().deletingLastPathComponent().path == nexus.rootURL.path
        )
    }

    @Test("taskFileURL resolves into a renamed Tasks singleton after sidecar discovery")
    func taskFileURLFollowsRenamedSingleton() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let renamed = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: renamed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(
            to: renamed.appendingPathComponent(NexusPaths.taskConfigSidecarFilename)
        )

        let url = NexusPaths.taskFileURL(forTitle: "Pay bills", in: nexus)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Errands")
        #expect(url.lastPathComponent == "Pay bills.task.json")
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
