import Foundation
import Testing

@testable import Pommora

/// Tests for `ItemTypeDetailRowComposer` — the pure-data row builder that
/// backs `ItemTypeDetailView`'s table. Extracted from the view so unit tests
/// can verify row order + nesting without instantiating SwiftUI.
@Suite("ItemTypeDetailViewTests")
@MainActor
struct ItemTypeDetailViewTests {

    // MARK: - Helpers

    @discardableResult
    private func makeItemType(nexus: Nexus, title: String) throws -> ItemType {
        let itemType = ItemType(
            id: ULID.generate(), title: title, icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        let folderURL = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title))
        return itemType
    }

    // MARK: - Test 1: Composition order — Sets first, then root Items

    @Test("rows() composes Sets first, then root Items, both as DetailRow")
    func rowsCompositionOrder() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let type = try makeItemType(nexus: nexus, title: "Recipes")

        let itemTypeManager = ItemTypeManager(nexus: nexus)
        await itemTypeManager.loadAll()

        try await itemTypeManager.createItemCollection(name: "Mains", inItemType: type)
        try await itemTypeManager.createItemCollection(name: "Sides", inItemType: type)

        // Re-fetch the type (mutated by collection creates).
        guard let typeRef = itemTypeManager.types.first(where: { $0.id == type.id }) else {
            Issue.record("Type missing after create-collection round-trip")
            return
        }

        let itemContentManager = ItemContentManager(
            nexus: nexus, contextProvider: { NexusContext.empty }
        )
        let rootItem = try await itemContentManager.createItem(name: "Quick", inTypeRoot: typeRef)

        let composer = ItemTypeDetailRowComposer(
            type: typeRef,
            itemTypeManager: itemTypeManager,
            itemContentManager: itemContentManager
        )
        let rows = composer.rows()

        #expect(rows.count == 3)
        #expect(rows[0].id.hasPrefix("set-"))
        #expect(rows[1].id.hasPrefix("set-"))
        #expect(rows[2].id == rootItem.id)
        #expect(rows[2].title == "Quick")
    }

    // MARK: - Test 2: Set rows carry child Items

    @Test("rows() nests Items inside their parent Set as children")
    func setRowsCarryChildItems() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let type = try makeItemType(nexus: nexus, title: "Recipes")

        let itemTypeManager = ItemTypeManager(nexus: nexus)
        await itemTypeManager.loadAll()
        try await itemTypeManager.createItemCollection(name: "Mains", inItemType: type)

        guard let typeRef = itemTypeManager.types.first(where: { $0.id == type.id }),
            let set = itemTypeManager.itemCollections(in: typeRef).first
        else {
            Issue.record("Type / collection missing")
            return
        }

        let itemContentManager = ItemContentManager(
            nexus: nexus, contextProvider: { NexusContext.empty }
        )
        let item = try await itemContentManager.createItem(name: "Pasta", in: set, type: typeRef)

        let composer = ItemTypeDetailRowComposer(
            type: typeRef,
            itemTypeManager: itemTypeManager,
            itemContentManager: itemContentManager
        )
        let rows = composer.rows()

        #expect(rows.count == 1)
        #expect(rows[0].title == "Mains")
        #expect(rows[0].children?.count == 1)
        #expect(rows[0].children?.first?.id == item.id)
        #expect(rows[0].children?.first?.title == "Pasta")
    }
}
