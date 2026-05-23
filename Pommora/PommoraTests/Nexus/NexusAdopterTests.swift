import Foundation
import Testing

@testable import Pommora

/// NexusAdopter tests for the ParadigmV2 Phase 6 wrapper layout.
///
/// PageType folders live at `<nexus>/Pages/<Type>/`; ItemType folders at
/// `<nexus>/Items/<Type>/`. Folders sitting at the nexus root that aren't one
/// of the reserved wrapper names (`Pages`, `Items`, `Agenda`) are surfaced
/// via `skippedTopLevel` — Phase 10's user-data migration owns relocating
/// legacy-shaped folders into `Pages/`.
@MainActor
@Suite("NexusAdopter")
struct NexusAdopterTests {

    // MARK: - scan: Pages-side

    @Test("scan returns empty plan for an empty folder")
    func scanEmpty() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.vaults.isEmpty)
        #expect(plan.collections.isEmpty)
        #expect(plan.itemTypes.isEmpty)
        #expect(plan.itemCollections.isEmpty)
        #expect(plan.pagesPreviewCount == 0)
        #expect(plan.itemsPreviewCount == 0)
        #expect(plan.skippedTopLevel.isEmpty)
        #expect(!plan.hasAnythingToAdopt)
    }

    @Test("scan proposes PageType for folder inside Pages/ without _schema.json")
    func scanProposesVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.vaults.count == 1)
        #expect(plan.vaults.first?.title == "Projects")
        #expect(plan.vaults.first?.folderURL.lastPathComponent == "Projects")
        // Sanity: PageType folder lives inside the Pages/ wrapper
        #expect(plan.vaults.first?.folderURL.deletingLastPathComponent().lastPathComponent == "Pages")
    }

    @Test("scan skips PageType folder that already has _schema.json (idempotent)")
    func scanSkipsExistingVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: metaURL
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.vaults.isEmpty)
    }

    @Test("scan proposes PageCollection for sub-folder under a PageType without _schema.json")
    func scanProposesCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.collections.count == 1)
        #expect(plan.collections.first?.title == "Active")
        #expect(plan.collections.first?.vaultFolderURL.lastPathComponent == "Projects")
    }

    @Test("scan skips PageCollection sub-folder that already has _schema.json")
    func scanSkipsExistingCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HC","type_id":"01HV","modified_at":"2026-05-01T00:00:00Z"}"#,
            to: sub.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        // PageType is still proposed (no _schema.json on the PageType folder yet),
        // but the existing sub-folder sidecar means the PageCollection is NOT re-proposed.
        #expect(plan.vaults.count == 1)
        #expect(plan.collections.isEmpty)
    }

    @Test("scan excludes hidden + underscore-prefixed folders inside Pages/")
    func scanExcludesHiddenInsidePages() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let pagesWrapper = NexusPaths.pagesWrapperDir(in: nexus.rootURL)
        try FileManager.default.createDirectory(at: pagesWrapper, withIntermediateDirectories: true)

        for name in [".hidden", "_internal", "Real"] {
            try FileManager.default.createDirectory(
                at: pagesWrapper.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        // Only "Real" should be proposed; hidden + underscore-prefixed are excluded.
        #expect(plan.vaults.count == 1)
        #expect(plan.vaults.first?.title == "Real")
    }

    @Test("scan counts .md descendants under Pages/ and .json under Items/")
    func scanCountsRecursive() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Pages-side fixture: PageType + PageCollection sub-folder + nested .md files
        let vault = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        let coll = vault.appendingPathComponent("Active", isDirectory: true)
        let deep = coll.appendingPathComponent("deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FixtureFiles.write("# Top", to: vault.appendingPathComponent("Top.md"))
        try FixtureFiles.write("# Deep", to: deep.appendingPathComponent("Deep.md"))

        // Items-side fixture: ItemType + ItemCollection + one .json item
        let itemType = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        let itemColl = itemType.appendingPathComponent("Groceries", isDirectory: true)
        try FileManager.default.createDirectory(at: itemColl, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HI","created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z","description":"","tier1":[],"tier2":[],"tier3":[],"properties":{}}"#,
            to: itemColl.appendingPathComponent("Buy milk.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.pagesPreviewCount == 2)
        #expect(plan.itemsPreviewCount == 1)
    }

    // MARK: - scan: Items-side

    @Test("scan proposes ItemType for folder inside Items/ without _schema.json")
    func scanProposesItemType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.itemTypes.count == 1)
        #expect(plan.itemTypes.first?.title == "Errands")
        #expect(
            plan.itemTypes.first?.folderURL.deletingLastPathComponent().lastPathComponent == "Items"
        )
    }

    @Test("scan proposes ItemCollection for sub-folder under an ItemType")
    func scanProposesItemCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let itemType = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        let sub = itemType.appendingPathComponent("Groceries", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.itemTypes.count == 1)
        #expect(plan.itemCollections.count == 1)
        #expect(plan.itemCollections.first?.title == "Groceries")
        #expect(
            plan.itemCollections.first?.itemTypeFolderURL.lastPathComponent == "Errands"
        )
    }

    @Test("scan skips ItemType folder that already has _schema.json")
    func scanSkipsExistingItemType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HIT","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.itemTypes.isEmpty)
    }

    // MARK: - scan: skippedTopLevel (legacy-shaped folders at nexus root)

    @Test("scan records non-wrapper top-level folders in skippedTopLevel")
    func scanRecordsLegacyTopLevel() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let root = nexus.rootURL
        // Legacy-shaped folders sitting at the nexus root — Phase 10 migration territory.
        for name in ["LegacyPlanner", "OldMaterials", "node_modules", "_internal"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        let skippedNames = Set(plan.skippedTopLevel.map { $0.lastPathComponent })
        // node_modules + _internal are filtered out (excluded / underscore-prefixed).
        // LegacyPlanner + OldMaterials surface as skipped.
        #expect(skippedNames.contains("LegacyPlanner"))
        #expect(skippedNames.contains("OldMaterials"))
        #expect(!skippedNames.contains("node_modules"))
        #expect(!skippedNames.contains("_internal"))

        // Legacy-shaped folders are NOT adopted as PageTypes — only Pages/ contents are.
        #expect(plan.vaults.isEmpty)
    }

    @Test("scan does NOT add reserved wrapper names (Pages, Items, Agenda) to skippedTopLevel")
    func scanIgnoresReservedWrappersInSkipped() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Materialize all three wrappers — they should not appear in skippedTopLevel.
        for wrapper in [
            NexusPaths.pagesWrapperDir(in: nexus.rootURL),
            NexusPaths.itemsWrapperDir(in: nexus.rootURL),
            NexusPaths.agendaWrapperDir(in: nexus.rootURL),
        ] {
            try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        let skippedNames = Set(plan.skippedTopLevel.map { $0.lastPathComponent })
        #expect(!skippedNames.contains("Pages"))
        #expect(!skippedNames.contains("Items"))
        #expect(!skippedNames.contains("Agenda"))
        #expect(plan.skippedTopLevel.isEmpty)
    }

    // MARK: - apply

    @Test("apply on an empty nexus creates Pages/, Items/, Agenda/Tasks/, Agenda/Events/ wrappers")
    func applyCreatesWrappersOnEmptyNexus() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let pages = NexusPaths.pagesWrapperDir(in: nexus.rootURL)
        let items = NexusPaths.itemsWrapperDir(in: nexus.rootURL)
        let agenda = NexusPaths.agendaWrapperDir(in: nexus.rootURL)
        let tasks = agenda.appendingPathComponent("Tasks", isDirectory: true)
        let events = agenda.appendingPathComponent("Events", isDirectory: true)

        var isDir: ObjCBool = false
        for url in [pages, items, agenda, tasks, events] {
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
    }

    @Test("apply writes PageType _schema.json into existing folder under Pages/")
    func applyWritesVaultSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: metaURL.path))

        let vault = try PageType.load(from: metaURL)
        #expect(vault.title == "Projects")
        #expect(!vault.id.isEmpty)
    }

    @Test("apply writes PageCollection _schema.json with parent PageType's id")
    func applyLinksCollectionToVault() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let vaultMetaURL = vault.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let collMetaURL = sub.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let vaultModel = try PageType.load(from: vaultMetaURL)
        let collModel = try PageCollection.load(from: collMetaURL)

        #expect(collModel.typeID == vaultModel.id)
        #expect(collModel.title == "Active")
    }

    @Test("apply writes ItemType _schema.json into existing folder under Items/")
    func applyWritesItemTypeSidecar() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: metaURL.path))

        let itemType = try ItemType.load(from: metaURL)
        #expect(itemType.title == "Errands")
        #expect(!itemType.id.isEmpty)
    }

    @Test("apply writes ItemCollection _schema.json with parent ItemType's id")
    func applyLinksItemCollectionToItemType() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let itemType = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        let sub = itemType.appendingPathComponent("Groceries", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let itemTypeMetaURL = itemType.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let collMetaURL = sub.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let itemTypeModel = try ItemType.load(from: itemTypeMetaURL)
        let collModel = try ItemCollection.load(from: collMetaURL)

        #expect(collModel.typeID == itemTypeModel.id)
        #expect(collModel.title == "Groceries")
    }

    @Test("scan+apply is idempotent — second pass writes nothing new")
    func idempotent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let vault = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        let sub = vault.appendingPathComponent("Active", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let itemType = NexusPaths.itemTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Errands"
        )
        let itemSub = itemType.appendingPathComponent("Groceries", isDirectory: true)
        try FileManager.default.createDirectory(at: itemSub, withIntermediateDirectories: true)

        let plan1 = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan1)

        let plan2 = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan2.vaults.isEmpty)
        #expect(plan2.collections.isEmpty)
        #expect(plan2.itemTypes.isEmpty)
        #expect(plan2.itemCollections.isEmpty)
        #expect(!plan2.hasAnythingToAdopt)
    }

    @Test("apply preserves PageType id across re-load")
    func vaultIDStable() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Projects"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let metaURL = folder.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let first = try PageType.load(from: metaURL)
        let second = try PageType.load(from: metaURL)
        #expect(first.id == second.id)
    }

    @Test("legacy PageType folder at nexus root is NOT adopted; surfaces in skippedTopLevel")
    func legacyRootFolderNotAdopted() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Pre-ParadigmV2 shape: PageType folder living directly at the nexus root.
        let legacy = nexus.rootURL.appendingPathComponent("Planner", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        // The legacy folder is recorded as skipped, NOT adopted as a PageType.
        // (Empty folder with no sidecar and no content hints is treated as
        // non-Pommora and left untouched.)
        #expect(plan.vaults.isEmpty)
        let skippedNames = Set(plan.skippedTopLevel.map { $0.lastPathComponent })
        #expect(skippedNames.contains("Planner"))
    }

    // MARK: - scan + apply: legacy-layout migrations (Phase 10 scope pulled into adopter)

    @Test("scan plans Pages-side migration for legacy root folder containing .md files")
    func scanPlansPagesSideMigrationForMarkdownContent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Pre-ParadigmV2 shape: legacy PageType folder at nexus root, with the
        // already-auto-healed `_schema.json` sidecar and a stray .md page.
        let legacy = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HV","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )
        try FixtureFiles.write("# Soup", to: legacy.appendingPathComponent("Soup.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.legacyMigrations.count == 1)
        let mig = try #require(plan.legacyMigrations.first)
        #expect(mig.title == "Recipes")
        #expect(mig.side == .pages)
        #expect(mig.detectedBy == .markdownChildren)
        #expect(!mig.needsFreshSidecar)
        // Destination is inside the Pages/ wrapper.
        #expect(mig.destinationFolderURL.deletingLastPathComponent().lastPathComponent == "Pages")
        #expect(mig.destinationFolderURL.lastPathComponent == "Recipes")
        // The Recipes folder MUST NOT appear in skippedTopLevel — it's been
        // promoted into the legacy-migration bucket.
        let skippedNames = Set(plan.skippedTopLevel.map { $0.lastPathComponent })
        #expect(!skippedNames.contains("Recipes"))
    }

    @Test("scan plans Items-side migration for legacy root folder containing user .json files")
    func scanPlansItemsSideMigrationForJSONContent() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let legacy = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HIT","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )
        // User-namespaced .json item (filename does NOT start with `_`).
        try FixtureFiles.writeJSON(
            #"{"id":"01HI","created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z","description":"","tier1":[],"tier2":[],"tier3":[],"properties":{}}"#,
            to: legacy.appendingPathComponent("Buy milk.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.legacyMigrations.count == 1)
        let mig = try #require(plan.legacyMigrations.first)
        #expect(mig.title == "Errands")
        #expect(mig.side == .items)
        #expect(mig.detectedBy == .jsonChildren)
        #expect(mig.destinationFolderURL.deletingLastPathComponent().lastPathComponent == "Items")
        #expect(mig.destinationFolderURL.lastPathComponent == "Errands")
    }

    @Test("scan defaults sidecar-only legacy folder (empty) to Pages-side")
    func scanDefaultsEmptyLegacyFolderToPages() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let legacy = nexus.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        // Sidecar present but no .md / .json content — pre-ParadigmV2 canonical
        // shape was always Pages-side, so the adopter defaults there.
        try FixtureFiles.writeJSON(
            #"{"id":"01HV2","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.legacyMigrations.count == 1)
        let mig = try #require(plan.legacyMigrations.first)
        #expect(mig.side == .pages)
        #expect(mig.detectedBy == .emptyFolderDefaultsToPages)
    }

    @Test("scan never plans migration for reserved wrapper names (Pages, Items, Agenda)")
    func scanNeverMigratesReservedWrappers() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Materialize all three wrappers with sidecars to confirm the reserved-name
        // filter takes precedence over the sidecar-detection signal.
        for wrapper in [
            NexusPaths.pagesWrapperDir(in: nexus.rootURL),
            NexusPaths.itemsWrapperDir(in: nexus.rootURL),
            NexusPaths.agendaWrapperDir(in: nexus.rootURL),
        ] {
            try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        }

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.legacyMigrations.isEmpty)
        let skippedNames = Set(plan.skippedTopLevel.map { $0.lastPathComponent })
        #expect(!skippedNames.contains("Pages"))
        #expect(!skippedNames.contains("Items"))
        #expect(!skippedNames.contains("Agenda"))
    }

    @Test("apply relocates Pages-side legacy folder into Pages/ wrapper")
    func applyRelocatesPagesSideLegacyFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let legacy = nexus.rootURL.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVREC","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )
        try FixtureFiles.write("# Soup", to: legacy.appendingPathComponent("Soup.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let movedRoot = nexus.rootURL
            .appendingPathComponent("Pages", isDirectory: true)
            .appendingPathComponent("Recipes", isDirectory: true)
        let sidecar = movedRoot.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        let movedPage = movedRoot.appendingPathComponent("Soup.md")
        #expect(FileManager.default.fileExists(atPath: movedRoot.path))
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(FileManager.default.fileExists(atPath: movedPage.path))
        // Source no longer exists at root.
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        // Original sidecar id preserved (the move is a rename, not a fresh write).
        let pageType = try PageType.load(from: sidecar)
        #expect(pageType.id == "01HVREC")
    }

    @Test("apply relocates Items-side legacy folder into Items/ wrapper")
    func applyRelocatesItemsSideLegacyFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let legacy = nexus.rootURL.appendingPathComponent("Errands", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HITERR","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        )
        try FixtureFiles.writeJSON(
            #"{"id":"01HI","created_at":"2026-05-01T00:00:00Z","modified_at":"2026-05-01T00:00:00Z","description":"","tier1":[],"tier2":[],"tier3":[],"properties":{}}"#,
            to: legacy.appendingPathComponent("Buy milk.json")
        )

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let movedRoot = nexus.rootURL
            .appendingPathComponent("Items", isDirectory: true)
            .appendingPathComponent("Errands", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: movedRoot.path))
        #expect(
            FileManager.default.fileExists(
                atPath: movedRoot.appendingPathComponent(NexusPaths.schemaSidecarFilename).path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: movedRoot.appendingPathComponent("Buy milk.json").path
            )
        )
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("apply writes fresh sidecar when legacy folder lacks one")
    func applyWritesFreshSidecarForBareLegacyFolder() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Bare folder with .md content but no sidecar — scan should mark
        // needsFreshSidecar=true; apply must write one post-move.
        let legacy = nexus.rootURL.appendingPathComponent("Journal", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.write("# Today", to: legacy.appendingPathComponent("Today.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.legacyMigrations.count == 1)
        #expect(plan.legacyMigrations.first?.needsFreshSidecar == true)

        try NexusAdopter.apply(plan)

        let movedRoot = nexus.rootURL
            .appendingPathComponent("Pages", isDirectory: true)
            .appendingPathComponent("Journal", isDirectory: true)
        let sidecar = movedRoot.appendingPathComponent(NexusPaths.schemaSidecarFilename)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        let pageType = try PageType.load(from: sidecar)
        #expect(pageType.title == "Journal")
        #expect(!pageType.id.isEmpty)
    }

    @Test("apply renames legacy _vault.json to _schema.json post-move")
    func applyRenamesLegacyVaultSidecarPostMove() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Pre-auto-heal layout: legacy `_vault.json` sidecar at nexus root.
        let legacy = nexus.rootURL.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.writeJSON(
            #"{"id":"01HVLEGACY","modified_at":"2026-05-01T00:00:00Z","properties":[],"views":[]}"#,
            to: legacy.appendingPathComponent("_vault.json")
        )
        try FixtureFiles.write("# Old", to: legacy.appendingPathComponent("Old.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        try NexusAdopter.apply(plan)

        let movedRoot = nexus.rootURL
            .appendingPathComponent("Pages", isDirectory: true)
            .appendingPathComponent("Legacy", isDirectory: true)
        #expect(
            FileManager.default.fileExists(
                atPath: movedRoot.appendingPathComponent(NexusPaths.schemaSidecarFilename).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: movedRoot.appendingPathComponent("_vault.json").path
            )
        )
    }

    @Test("apply fails gracefully when destination already exists")
    func applyFailsGracefullyOnDestinationCollision() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        // Legacy source folder...
        let legacy = nexus.rootURL.appendingPathComponent("Conflict", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FixtureFiles.write("# Old", to: legacy.appendingPathComponent("Old.md"))
        // ...and a pre-existing folder with the same name at the destination.
        let collision = NexusPaths.pageTypeFolderURL(
            in: nexus.rootURL, typeFolderName: "Conflict"
        )
        try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)
        try FixtureFiles.write("# Existing", to: collision.appendingPathComponent("Existing.md"))

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)
        #expect(plan.legacyMigrations.count == 1)

        // The collision is surfaced as a partialFailure; the source folder is
        // left in place so the user can resolve manually.
        var thrownFailure: AdoptionError?
        do {
            try NexusAdopter.apply(plan)
        } catch let error as AdoptionError {
            thrownFailure = error
        }
        let failure = try #require(thrownFailure)
        if case .partialFailure(let urls) = failure {
            #expect(urls.contains(legacy))
        } else {
            Issue.record("expected .partialFailure for the colliding migration")
        }
        // Source folder is preserved on collision; existing destination untouched.
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(
            FileManager.default.fileExists(
                atPath: collision.appendingPathComponent("Existing.md").path
            )
        )
    }
}
