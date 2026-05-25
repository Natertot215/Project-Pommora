import Foundation
import Testing

@testable import Pommora

/// Tests for `ItemCollectionDetailRowComposer` — the flat Item-row builder
/// behind `ItemCollectionDetailView`'s table. Also verifies the breadcrumb
/// back-out logic via `ItemTypeManager.parentItemType(for:)`.
@Suite("ItemCollectionDetailViewTests")
@MainActor
struct ItemCollectionDetailViewTests {

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

    // MARK: - Test 1: Composition — flat Items

    @Test("rows() returns Items in the Set as flat DetailRows")
    func rowsFlatItems() async throws {
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
        let a = try await itemContentManager.createItem(name: "Pasta", in: set, type: typeRef)
        let b = try await itemContentManager.createItem(name: "Salad", in: set, type: typeRef)

        let composer = ItemCollectionDetailRowComposer(
            collection: set,
            itemContentManager: itemContentManager
        )
        let rows = composer.rows()

        #expect(rows.count == 2)
        #expect(rows.contains { $0.id == a.id })
        #expect(rows.contains { $0.id == b.id })
        #expect(rows.allSatisfy { $0.children == nil })
    }

    // MARK: - Test 2: Breadcrumb back-out

    @Test("Breadcrumb back-out resolves parent ItemType via ItemTypeManager.parentItemType")
    func breadcrumbResolvesParent() async throws {
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

        let parent = itemTypeManager.parentItemType(for: set)
        #expect(parent?.id == typeRef.id)
    }
}
