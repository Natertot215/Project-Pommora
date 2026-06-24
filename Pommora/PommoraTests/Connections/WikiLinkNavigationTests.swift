import Foundation
import GRDB
import Testing

@testable import Pommora

/// E2: a clicked `[[Title]]` resolves to a navigable `.page` selection by reusing
/// the index (resolveUniqueTitle + entityContainer), D1's ConnectionFileLocator,
/// and a fresh disk load. Mirrors `ConnectionLiveUpdateTests.setup()` — a real
/// on-disk page plus its index rows so BOTH the index lookup and the load succeed.
@MainActor
@Suite("WikiLinkNavigationTests")
struct WikiLinkNavigationTests {

    // MARK: - Fixture

    private func setup() async throws -> (
        nexus: Nexus,
        vault: PageType,
        coll: PageSet,
        manager: PageContentManager,
        index: PommoraIndex
    ) {
        let nexus = try TempNexus.make()
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(),
            parentID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let updater = IndexUpdater(index)
        try updater.upsertPageType(vault)
        try updater.upsertPageCollection(coll)

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = updater

        return (nexus, vault, coll, manager, index)
    }

    // MARK: - Test 1: resolves a real on-disk page

    @Test("clicking a resolved title returns the page selection")
    func resolvesExistingTitle() async throws {
        let (nexus, vault, coll, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let target = try await manager.createPage(name: "Target", in: coll, vault: vault)

        let selection = await WikiLinkPageOpener.pageSelection(
            forTitle: "Target", index: index, nexusRootURL: nexus.rootURL)

        guard case .page(let meta) = selection else {
            Issue.record("expected .page selection, got \(String(describing: selection))")
            return
        }
        #expect(meta.id == target.id)
        #expect(meta.title == "Target")
    }

    // MARK: - Test 2: a missing title resolves to nil

    @Test("clicking a missing title returns nil")
    func missingTitleReturnsNil() async throws {
        let (nexus, _, _, _, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let selection = await WikiLinkPageOpener.pageSelection(
            forTitle: "Nope", index: index, nexusRootURL: nexus.rootURL)

        #expect(selection == nil)
    }

    // MARK: - Test 3: a duplicate (ambiguous) title resolves to nil

    @Test("clicking an ambiguous duplicate title returns nil")
    func duplicateTitleReturnsNil() async throws {
        let (nexus, vault, coll, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // One real on-disk page named "Dupe"…
        let first = try await manager.createPage(name: "Dupe", in: coll, vault: vault)
        // …plus a second index row with the SAME title under the Vault root.
        // resolveUniqueTitle must now find 2 matches and return nil (ambiguous).
        let twin = PageMeta(
            id: ULID.generate(), title: "Dupe", url: first.url, frontmatter: first.frontmatter)
        try IndexUpdater(index).upsertPage(twin, pageTypeID: vault.id, pageCollectionID: nil)

        let selection = await WikiLinkPageOpener.pageSelection(
            forTitle: "Dupe", index: index, nexusRootURL: nexus.rootURL)

        #expect(selection == nil)
    }
}
