import Foundation
import Testing

@testable import Pommora

/// NexusAdopter tests for the v0.3.0 flat layout — four input shapes
/// (fresh / legacy v0.2 / paradigmV2 wrapper / already flat). See
/// `Planning/v0.3.0-Flat-Layout-Plan.md` Phase 4 + 5.2.
@MainActor
@Suite("NexusAdopter")
struct NexusAdopterTests {

    // MARK: - scan: empty / fresh

    @Test("scan returns empty plan for an empty folder")
    func scanEmpty() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.isEmpty)
        #expect(plan.inPlaceRenames.isEmpty)
        #expect(plan.unwrapSteps.isEmpty)
        #expect(plan.alreadyFlat.isEmpty)
        #expect(plan.warnings.isEmpty)
        #expect(!plan.hasAnythingToAdopt)
    }

    @Test("scan classifies bare empty folder as fresh-PageType (defaults to Pages)")
    func scanBareFolderDefaultsToPages() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageType)
        #expect(plan.freshSidecars.first?.title == "Notes")
    }

    @Test("scan classifies folder with .md content as fresh-PageType")
    func scanMarkdownContentSignalsPageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Today", to: folder.appendingPathComponent("Today.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageType)
    }

    @Test("scan classifies folder with user .json content as fresh-ItemType")
    func scanJSONContentSignalsItemType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HI"}"#,
            to: folder.appendingPathComponent("Buy milk.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .itemType)
    }

    // MARK: - scan: fresh folders don't trigger adoption preview

    @Test("adoptionNoOpOnUnPommoraFoldersAtRoot")
    func adoptionNoOpOnUnPommoraFoldersAtRoot() async throws {
        // Given a Nexus root with several non-Pommora folders (no sidecars) —
        // mimics Nathan's real Nexus shape where Obsidian-managed folders and
        // personal organization folders live alongside Pommora-recognized
        // entities.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        for name in ["Inbox", "Reference", "Random Notes", "Project Pommora"] {
            let folder = nexus.rootURL.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Mix some content so the content-sniff picks a kind — these would
            // otherwise be proposed as fresh PageType candidates on every launch.
            try FixtureFiles.write(
                "# Stray", to: folder.appendingPathComponent("Stray.md")
            )
        }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        // Then the plan classifies them as freshSidecars (scan still detects
        // them — the classification surface is unchanged).
        #expect(plan.freshSidecars.count > 0)

        // But hasAnythingToAdopt should be FALSE — they're non-Pommora user
        // folders. Per-folder adoption UI is a future Prospect; bulk
        // launch-time prompts are too noisy for real Nexus roots.
        #expect(plan.hasAnythingToAdopt == false)
    }

    // MARK: - scan: legacy v0.2 (in-place rename)

    @Test("scan classifies folder with _vault.json as legacy-v0.2 in-place rename")
    func scanLegacyVaultSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVREC","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent("_vault.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.inPlaceRenames.count == 1)
        let rename = try #require(plan.inPlaceRenames.first)
        #expect(rename.folderURL == folder)
        #expect(rename.oldSidecar == "_vault.json")
        #expect(rename.newSidecar == NexusPaths.pageTypeSidecarFilename)
        #expect(rename.depth == .type)
    }

    @Test("scan plans collection renames inside legacy-v0.2 folder")
    func scanLegacyCollectionRenames() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Materials", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent("_vault.json")
        )
        let sub = folder.appendingPathComponent("Planning", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HC","type_id":"01HV","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: sub.appendingPathComponent("_collection.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.inPlaceRenames.count == 2)
        let typeRename = plan.inPlaceRenames.first { $0.depth == .type }
        let collRename = plan.inPlaceRenames.first { $0.depth == .collection }
        #expect(typeRename?.newSidecar == NexusPaths.pageTypeSidecarFilename)
        #expect(collRename?.newSidecar == NexusPaths.pageCollectionSidecarFilename)
    }

    // MARK: - scan: paradigmV2 wrapper

    @Test("scan classifies Pages/ folder as wrapper-unwrap")
    func scanPagesWrapper() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let child = wrapper.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: child.appendingPathComponent("_schema.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.unwrapSteps.count == 1)
        let unwrap = try #require(plan.unwrapSteps.first)
        #expect(unwrap.wrapperKind == .pages)
        #expect(unwrap.moves.count == 1)
        let move = try #require(unwrap.moves.first)
        #expect(move.sourceURL.lastPathComponent == "Recipes")
        #expect(move.destURL.lastPathComponent == "Recipes")
        #expect(move.typeSidecar == .pageType)
        #expect(move.collectionSidecar == .pageCollection)
    }

    @Test("scan classifies Items/ folder as wrapper-unwrap when child has _schema.json")
    func scanItemsWrapper() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Items", isDirectory: true)
        let child = wrapper.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        // Child must carry a legacy sidecar so the structural guard recognizes
        // this as a real wrapper (not a user folder named "Items").
        try FixtureFiles.writeJSON(
            #"{"id":"01HVIT","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: child.appendingPathComponent("_schema.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let unwrap = try #require(plan.unwrapSteps.first)
        #expect(unwrap.wrapperKind == .items)
        #expect(unwrap.moves.first?.typeSidecar == .itemType)
        #expect(unwrap.moves.first?.collectionSidecar == .itemCollection)
    }

    @Test("scan classifies Agenda/ Tasks + Events as wrapper-unwrap with per-singleton sidecars")
    func scanAgendaWrapper() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
        let tasks = wrapper.appendingPathComponent("Tasks", isDirectory: true)
        let events = wrapper.appendingPathComponent("Events", isDirectory: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        // Children must carry _schema.json so the structural guard recognizes
        // this as a real ParadigmV2 Agenda wrapper.
        try FixtureFiles.writeJSON(
            #"{"schema_version":1,"properties":[],"views":[],"modified_at":"2026-05-01T00:00:00Z"}"#,
            to: tasks.appendingPathComponent("_schema.json")
        )
        try FixtureFiles.writeJSON(
            #"{"schema_version":1,"properties":[],"views":[],"modified_at":"2026-05-01T00:00:00Z"}"#,
            to: events.appendingPathComponent("_schema.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let unwrap = try #require(plan.unwrapSteps.first)
        #expect(unwrap.wrapperKind == .agenda)
        let tasksMove = unwrap.moves.first { $0.sourceURL.lastPathComponent == "Tasks" }
        let eventsMove = unwrap.moves.first { $0.sourceURL.lastPathComponent == "Events" }
        #expect(tasksMove?.typeSidecar == .taskConfig)
        #expect(eventsMove?.typeSidecar == .eventConfig)
        // Agenda children have no collection layer.
        #expect(tasksMove?.collectionSidecar == nil)
        #expect(eventsMove?.collectionSidecar == nil)
    }

    // MARK: - scan: already flat

    @Test("scan classifies folder with _pagetype.json as already-flat")
    func scanAlreadyFlatPageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.alreadyFlat.count == 1)
        #expect(plan.alreadyFlat.first?.kind == .pageType)
        #expect(plan.freshSidecars.isEmpty)
        #expect(plan.inPlaceRenames.isEmpty)
    }

    // MARK: - scan: pathological (silent cleanup)

    @Test("scan silently classifies dual-sidecar folders as flat (cleanup at apply)")
    func scanSilentlyClassifiesDualSidecarsAsFlat() throws {
        // Folders carrying multiple recognized per-kind sidecars are classified
        // as alreadyFlat with the FIRST-FOUND sidecar (per recognizedSidecarsAt
        // order: pageType > itemType > ...). The non-authoritative sidecar is
        // cleaned up at apply time via cleanupLegacyOrphans — NOT surfaced as
        // a warning, because this fires routinely on nexuses migrated through
        // early flatlayout-4.2 versions and the cleanup is non-destructive.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Weird", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HIT","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.alreadyFlat.count == 1)
        #expect(plan.warnings.isEmpty)  // silent — cleanup pass handles the orphan
        #expect(plan.hasAnythingToAdopt == false)  // no preview shown
    }

    @Test("apply deletes co-located per-kind sidecar orphan")
    func applyCleansUpCoLocatedPerKindOrphan() throws {
        // Apply pass deletes the non-authoritative co-located sidecar on
        // already-flat folders (the bug-fix for Nathan's nexus state where
        // Materials/_pagecollection.json sat next to Materials/_pagetype.json
        // due to an early flatlayout-4.2 wrong-sidecar write).
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Materials", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )
        let orphanURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        try FixtureFiles.writeJSON(
            #"{"id":"01HC","type_id":"01HV","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: orphanURL
        )

        #expect(FileManager.default.fileExists(atPath: orphanURL.path) == true)
        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        _ = NexusAdopter.apply(plan)
        #expect(FileManager.default.fileExists(atPath: orphanURL.path) == false)
        // Authoritative sidecar preserved
        let typeURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: typeURL.path) == true)
    }

    // MARK: - scan: dotfile / underscore exclusion

    @Test("scan skips dotfile-prefixed and underscore-prefixed folders")
    func scanSkipsHiddenAndUnderscore() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        for name in [".obsidian", ".makemd", "_internal", "node_modules"] {
            try FileManager.default.createDirectory(
                at: nexus.rootURL.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.freshSidecars.isEmpty)
        #expect(plan.inPlaceRenames.isEmpty)
        #expect(plan.unwrapSteps.isEmpty)
    }

    // MARK: - apply: each shape

    @Test("apply on fresh PageType folder writes _pagetype.json")
    func applyFreshPageType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Soup", to: folder.appendingPathComponent("Soup.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result = NexusAdopter.apply(plan)

        let sidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        let pageType = try PageType.load(from: sidecar)
        #expect(pageType.title == "Recipes")
        #expect(result.failedCount == 0)
    }

    @Test("apply on legacy v0.2 folder renames _vault.json → _pagetype.json + preserves id")
    func applyLegacyRename() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVREC","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent("_vault.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result = NexusAdopter.apply(plan)

        let newSidecar = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        let oldSidecar = folder.appendingPathComponent("_vault.json")
        #expect(FileManager.default.fileExists(atPath: newSidecar.path))
        #expect(!FileManager.default.fileExists(atPath: oldSidecar.path))
        let pageType = try PageType.load(from: newSidecar)
        #expect(pageType.id == "01HVREC")
        #expect(result.failedCount == 0)
    }

    @Test("apply unwraps Pages/ wrapper to root + deletes wrapper")
    func applyUnwrapPagesWrapper() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let child = wrapper.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVREC","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: child.appendingPathComponent("_schema.json")
        )
        try FixtureFiles.write("# Soup", to: child.appendingPathComponent("Soup.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result = NexusAdopter.apply(plan)

        let movedRoot = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        let sidecar = movedRoot.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: movedRoot.path))
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(FileManager.default.fileExists(atPath: movedRoot.appendingPathComponent("Soup.md").path))
        // Old wrapper gone.
        #expect(!FileManager.default.fileExists(atPath: wrapper.path))
        // Sidecar id preserved through the schema → pagetype rename.
        let pageType = try PageType.load(from: sidecar)
        #expect(pageType.id == "01HVREC")
        #expect(result.failedCount == 0)
    }

    @Test("apply unwraps Agenda/Tasks/ → root Tasks/_taskconfig.json")
    func applyUnwrapAgendaTasks() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
        let tasks = wrapper.appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"schema_version":1,"properties":[],"views":[],"modified_at":"2026-05-01T00:00:00Z"}"#,
            to: tasks.appendingPathComponent("_schema.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        _ = NexusAdopter.apply(plan)

        let movedTasks = nexus.rootURL.appendingPathComponent("Tasks", isDirectory: true)
        let sidecar = movedTasks.appendingPathComponent(NexusPaths.taskConfigSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: movedTasks.path))
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(!FileManager.default.fileExists(atPath: wrapper.path))
    }

    @Test("apply is idempotent — second pass is a no-op")
    func applyIdempotent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.write("# Soup", to: folder.appendingPathComponent("Soup.md"))

        let plan1 = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        _ = NexusAdopter.apply(plan1)
        let plan2 = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result2 = NexusAdopter.apply(plan2)

        #expect(plan2.freshSidecars.isEmpty)
        #expect(plan2.inPlaceRenames.isEmpty)
        #expect(plan2.unwrapSteps.isEmpty)
        #expect(plan2.alreadyFlat.count == 1)
        #expect(result2.failedCount == 0)
    }

    // MARK: - apply: collision-on-unwrap

    @Test("apply handles unwrap collision by suffixing the moved folder with a timestamp")
    func applyUnwrapCollision() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Wrapper child wants to land at <nexus>/Recipes/...
        let wrapper = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let child = wrapper.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        // _schema.json is required so the structural guard recognizes this as
        // a real ParadigmV2 wrapper (not a user-named folder).
        try FixtureFiles.writeJSON(
            #"{"id":"01HVREC","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: child.appendingPathComponent("_schema.json")
        )
        try FixtureFiles.write("# Soup", to: child.appendingPathComponent("Soup.md"))
        // ...but a pre-existing folder already sits there.
        let collision = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)
        try FixtureFiles.write("# Existing", to: collision.appendingPathComponent("Existing.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result = NexusAdopter.apply(plan)

        // Pre-existing folder is untouched.
        #expect(FileManager.default.fileExists(atPath: collision.appendingPathComponent("Existing.md").path))
        // Collision handled — no per-folder failure recorded.
        #expect(result.failedCount == 0)
        // A timestamp-suffixed twin of Recipes now exists at the root.
        let rootContents = try FileManager.default.contentsOfDirectory(
            at: nexus.rootURL, includingPropertiesForKeys: nil, options: []
        )
        let suffixed = rootContents.first { url in
            let name = url.lastPathComponent
            return name.hasPrefix("Recipes.") && name != "Recipes"
        }
        #expect(suffixed != nil)
    }

    // MARK: - Nathan's concrete shape (paradigmV2 wrapper + co-located legacy orphans)

    @Test("apply on Nathan's actual shape: wrapper + co-located _vault/_schema → flat + orphans cleared")
    func applyNathansActualShape() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // <nexus>/Pages/Archives/ with BOTH _vault.json + _schema.json (Nathan's
        // real-disk scenario — paradigmV2 added _schema.json but didn't delete
        // the pre-existing _vault.json).
        let pages = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let archives = pages.appendingPathComponent("Archives", isDirectory: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVLEG","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: archives.appendingPathComponent("_vault.json")
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HVNEW","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: archives.appendingPathComponent("_schema.json")
        )
        // Materials with both AND a sub-folder also with both.
        let materials = pages.appendingPathComponent("Materials", isDirectory: true)
        let planning = materials.appendingPathComponent("Planning", isDirectory: true)
        try FileManager.default.createDirectory(at: planning, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVMAT","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: materials.appendingPathComponent("_vault.json")
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HVMATN","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: materials.appendingPathComponent("_schema.json")
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HC","type_id":"01HVMAT","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: planning.appendingPathComponent("_collection.json")
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HCNEW","type_id":"01HVMAT","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: planning.appendingPathComponent("_schema.json")
        )
        // Empty Items/ folder with only .DS_Store noise — no wrapper-shaped
        // children, so after the structural-guard fix it is treated as a fresh
        // PageType rather than unwrapped (the old pure-name-match behaviour was
        // the bug being fixed here).
        let items = nexus.rootURL.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        try FixtureFiles.write("noise", to: items.appendingPathComponent(".DS_Store"))
        // Agenda with Tasks + Events.
        let agenda = nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
        let tasks = agenda.appendingPathComponent("Tasks", isDirectory: true)
        let events = agenda.appendingPathComponent("Events", isDirectory: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"schema_version":1,"properties":[],"views":[],"modified_at":"2026-05-01T00:00:00Z"}"#,
            to: tasks.appendingPathComponent("_schema.json")
        )
        try FixtureFiles.writeJSON(
            #"{"schema_version":1,"properties":[],"views":[],"modified_at":"2026-05-01T00:00:00Z"}"#,
            to: events.appendingPathComponent("_schema.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result = NexusAdopter.apply(plan)

        // Real wrappers (with wrapper-shaped children) gone.
        #expect(!FileManager.default.fileExists(atPath: pages.path))
        #expect(!FileManager.default.fileExists(atPath: agenda.path))
        // The empty Items/ folder had no wrapper-shaped children, so the
        // structural guard correctly left it as a fresh PageType — it stays
        // on disk and receives a _pagetype.json sidecar.
        #expect(FileManager.default.fileExists(atPath: items.path))
        #expect(
            FileManager.default.fileExists(
                atPath: items.appendingPathComponent(NexusPaths.pageTypeSidecarFilename).path))

        // Archives at root with only _pagetype.json (legacy orphans deleted).
        let archivesNew = nexus.rootURL.appendingPathComponent("Archives", isDirectory: true)
        #expect(
            FileManager.default.fileExists(
                atPath: archivesNew.appendingPathComponent(NexusPaths.pageTypeSidecarFilename).path))
        #expect(!FileManager.default.fileExists(atPath: archivesNew.appendingPathComponent("_vault.json").path))
        #expect(!FileManager.default.fileExists(atPath: archivesNew.appendingPathComponent("_schema.json").path))

        // Materials/Planning sub-folder has only _pagecollection.json.
        let materialsNew = nexus.rootURL.appendingPathComponent("Materials", isDirectory: true)
        let planningNew = materialsNew.appendingPathComponent("Planning", isDirectory: true)
        #expect(
            FileManager.default.fileExists(
                atPath: planningNew.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename).path))
        #expect(!FileManager.default.fileExists(atPath: planningNew.appendingPathComponent("_collection.json").path))
        #expect(!FileManager.default.fileExists(atPath: planningNew.appendingPathComponent("_schema.json").path))

        // Tasks/Events at root with per-kind sidecars.
        let tasksNew = nexus.rootURL.appendingPathComponent("Tasks", isDirectory: true)
        let eventsNew = nexus.rootURL.appendingPathComponent("Events", isDirectory: true)
        #expect(
            FileManager.default.fileExists(
                atPath: tasksNew.appendingPathComponent(NexusPaths.taskConfigSidecarFilename).path))
        #expect(
            FileManager.default.fileExists(
                atPath: eventsNew.appendingPathComponent(NexusPaths.eventConfigSidecarFilename).path))

        #expect(result.failedCount == 0)
    }

    // MARK: - mixed input + failure isolation

    @Test("apply on mixed-shape nexus migrates each folder independently")
    func applyMixedShapes() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Shape #1 (fresh)
        let fresh = nexus.rootURL.appendingPathComponent("Fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try FixtureFiles.write("# Hi", to: fresh.appendingPathComponent("Hi.md"))
        // Shape #2 (legacy)
        let legacy = nexus.rootURL.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVL","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent("_vault.json")
        )
        // Shape #4 (already flat)
        let flat = nexus.rootURL.appendingPathComponent("Flat", isDirectory: true)
        try FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVF","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: flat.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let result = NexusAdopter.apply(plan)
        #expect(result.failedCount == 0)
        // Fresh got a sidecar.
        #expect(
            FileManager.default.fileExists(
                atPath: fresh.appendingPathComponent(NexusPaths.pageTypeSidecarFilename).path))
        // Legacy renamed.
        #expect(
            FileManager.default.fileExists(
                atPath: legacy.appendingPathComponent(NexusPaths.pageTypeSidecarFilename).path))
        #expect(!FileManager.default.fileExists(atPath: legacy.appendingPathComponent("_vault.json").path))
        // Flat untouched.
        #expect(
            FileManager.default.fileExists(atPath: flat.appendingPathComponent(NexusPaths.pageTypeSidecarFilename).path)
        )
    }

    // MARK: - wrapper detection: structural guard (Fix A)

    @Test("user-named Pages/ folder without legacy child sidecars is not unwrapped")
    func userNamedPagesFolderIsNotUnwrapped() throws {
        // A user folder coincidentally named "Pages" that carries only regular
        // .md content must NOT be destructively unwrapped. The structural guard
        // checks for _schema.json / _vault.json / _collection.json in children;
        // none present here → falls through to fresh PageType classification.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let pages = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let sub = pages.appendingPathComponent("MySubfolder", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FixtureFiles.write("# Essay", to: sub.appendingPathComponent("Essay.md"))
        try FixtureFiles.write("# Other", to: pages.appendingPathComponent("OtherEssay.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.unwrapSteps.isEmpty, "user Pages/ must not be unwrapped")
        let fresh = plan.freshSidecars.first { $0.folderURL.lastPathComponent == "Pages" }
        #expect(fresh != nil, "Pages/ should be classified as a fresh candidate")
        #expect(fresh?.kind == .pageType)
    }

    @Test("user-named Items/ folder without legacy child sidecars is not unwrapped")
    func userNamedItemsFolderIsNotUnwrapped() throws {
        // A user folder named "Items" with regular .json content (no legacy
        // child sidecars) must fall through to fresh ItemType classification.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let items = nexus.rootURL.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HI"}"#,
            to: items.appendingPathComponent("Buy milk.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.unwrapSteps.isEmpty, "user Items/ must not be unwrapped")
        let fresh = plan.freshSidecars.first { $0.folderURL.lastPathComponent == "Items" }
        #expect(fresh != nil)
        #expect(fresh?.kind == .itemType)
    }

    @Test("user-named Agenda/ folder without legacy child sidecars is not unwrapped")
    func userNamedAgendaFolderIsNotUnwrapped() throws {
        // A user folder named "Agenda" with .md content (no _schema.json etc.
        // in any child) must fall through to fresh PageType classification.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let agenda = nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
        try FileManager.default.createDirectory(at: agenda, withIntermediateDirectories: true)
        try FixtureFiles.write("# Meeting notes", to: agenda.appendingPathComponent("Notes.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.unwrapSteps.isEmpty, "user Agenda/ must not be unwrapped")
        let fresh = plan.freshSidecars.first { $0.folderURL.lastPathComponent == "Agenda" }
        #expect(fresh != nil)
        #expect(fresh?.kind == .pageType)
    }

    @Test("real ParadigmV2 Pages/ wrapper with _schema.json child still unwraps")
    func realParadigmV2WrapperStillUnwraps() throws {
        // The structural guard must not break real wrapper detection. A Pages/
        // folder whose child carries _schema.json is a genuine ParadigmV2
        // wrapper and must produce an unwrap step.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let child = wrapper.appendingPathComponent("MyVault", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: child.appendingPathComponent("_schema.json")
        )
        try FixtureFiles.write("# SomePage", to: child.appendingPathComponent("SomePage.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.unwrapSteps.count == 1, "real wrapper must produce an unwrap step")
        let unwrap = try #require(plan.unwrapSteps.first)
        #expect(unwrap.wrapperKind == .pages)
        #expect(unwrap.moves.first?.sourceURL.lastPathComponent == "MyVault")
        // Pages/ itself must NOT appear in freshSidecars.
        #expect(!plan.freshSidecars.contains(where: { $0.folderURL.lastPathComponent == "Pages" }))
    }

    @Test("empty user-named Pages/ folder with no children treated as fresh PageType")
    func emptyUserNamedPagesFolderTreatedAsFresh() throws {
        // An empty folder named "Pages" (no children at all) has no
        // wrapper-shaped children → structural guard returns false → fresh
        // PageType via emptyFolderDefaultsToPages. Must NOT be an unwrap.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let pages = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.unwrapSteps.isEmpty, "empty Pages/ must not be unwrapped")
        let fresh = plan.freshSidecars.first { $0.folderURL.lastPathComponent == "Pages" }
        #expect(fresh != nil)
        #expect(fresh?.kind == .pageType)
    }

    @Test("Pages/ with one legacy-shaped child AND one loose file triggers unwrap; loose file fate documented")
    func mixedPagesFolderUserPlusLegacy() throws {
        // Edge case: Pages/ contains MyVault/_schema.json (wrapper-shaped) AND
        // a loose RandomEssay.md at the Pages/ level. The presence of
        // _schema.json in a child is enough for folderHasWrapperShapedChildren
        // to return true, so the folder is treated as a wrapper.
        // The loose RandomEssay.md is NOT a folder — classifyWrapperFolder only
        // iterates childFolders — so it stays inside the Pages/ folder and is
        // NOT moved. After apply, Pages/ is deleted only if empty of meaningful
        // content; with RandomEssay.md still inside it will not be deleted.
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let wrapper = nexus.rootURL.appendingPathComponent("Pages", isDirectory: true)
        let child = wrapper.appendingPathComponent("MyVault", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: child.appendingPathComponent("_schema.json")
        )
        // Loose .md file directly inside Pages/ (not in a sub-folder).
        try FixtureFiles.write("# Random", to: wrapper.appendingPathComponent("RandomEssay.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        // Wrapper is recognized (legacy child present) and scheduled for unwrap.
        #expect(plan.unwrapSteps.count == 1)
        let unwrap = try #require(plan.unwrapSteps.first)
        #expect(unwrap.wrapperKind == .pages)
        #expect(unwrap.moves.first?.sourceURL.lastPathComponent == "MyVault")

        let result = NexusAdopter.apply(plan)
        #expect(result.failedCount == 0)

        // MyVault was moved to root.
        let movedVault = nexus.rootURL.appendingPathComponent("MyVault", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: movedVault.path))

        // Pages/ is NOT deleted — RandomEssay.md kept it non-empty.
        #expect(FileManager.default.fileExists(atPath: wrapper.path),
            "Pages/ stays on disk because RandomEssay.md prevents empty-wrapper deletion")
        #expect(FileManager.default.fileExists(atPath: wrapper.appendingPathComponent("RandomEssay.md").path))
    }
}
