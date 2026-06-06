import Foundation
import GRDB
import Testing

@testable import Pommora

/// E4: a clicked `{{Title}}` resolves to its `Item` by reusing the index
/// (resolveUniqueTitle + entityContainer), D1's ConnectionFileLocator, and a fresh
/// disk load — so a link to an item in an unloaded Set still opens. Mirrors
/// `WikiLinkNavigationTests` but for ITEMS (kind `.item`). Builds the manager via
/// the temp-nexus + IndexUpdater harness used by the item CRUD suites.
///
/// Suite/struct name matches the filename so `-only-testing:PommoraTests/ItemLinkNavigationTests`
/// resolves a non-zero executed count (quirk #18).
@MainActor
@Suite("ItemLinkNavigationTests")
struct ItemLinkNavigationTests {

    // MARK: - Fixture

    private func setup() async throws -> (
        nexus: Nexus,
        itemType: ItemType,
        manager: ItemContentManager,
        index: PommoraIndex
    ) {
        let nexus = try TempNexus.make()
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        let itemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "T")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: "T"))

        let updater = IndexUpdater(index)
        try updater.upsertItemType(itemType)

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        manager.indexUpdater = updater

        return (nexus, itemType, manager, index)
    }

    // MARK: - Test 1: resolves a real on-disk item

    @Test("clicking a resolved title returns the item")
    func resolvesExistingTitle() async throws {
        let (nexus, itemType, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let widget = try await manager.createItem(name: "Widget", inTypeRoot: itemType)

        let item = await ItemLinkOpener.loadItem(
            forTitle: "Widget", index: index, nexusRootURL: nexus.rootURL)

        #expect(item?.id == widget.id)
    }

    // MARK: - Test 2: a missing title resolves to nil

    @Test("clicking a missing title returns nil")
    func missingTitleReturnsNil() async throws {
        let (nexus, _, _, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        let item = await ItemLinkOpener.loadItem(
            forTitle: "Nope", index: index, nexusRootURL: nexus.rootURL)

        #expect(item == nil)
    }

    // MARK: - Test 3: a duplicate (ambiguous) title resolves to nil

    @Test("clicking an ambiguous duplicate title returns nil")
    func duplicateTitleReturnsNil() async throws {
        let (nexus, itemType, manager, index) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        // One real on-disk item named "Dupe"…
        let first = try await manager.createItem(name: "Dupe", inTypeRoot: itemType)
        // …plus a second index row with the SAME title under the same Type root.
        // resolveUniqueTitle must now find 2 matches and return nil (ambiguous).
        var twin = first
        twin.id = ULID.generate()
        try IndexUpdater(index).upsertItem(twin, itemTypeID: itemType.id, itemCollectionID: nil)

        let item = await ItemLinkOpener.loadItem(
            forTitle: "Dupe", index: index, nexusRootURL: nexus.rootURL)

        #expect(item == nil)
    }
}
