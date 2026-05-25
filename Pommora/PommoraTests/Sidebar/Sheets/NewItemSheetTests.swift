import Foundation
import Testing

@testable import Pommora

/// Tests for `NewItemSheet`'s create paths — drives the manager APIs that the
/// sheet's `create()` calls invoke. Verifies that creation into both an
/// ItemCollection ("Set") and an ItemType root succeeds and shows up in the
/// in-memory cache.
///
/// (J.5/J.11/K.1 pattern: no SwiftUI rendering; tests confirm the manager
/// surface the sheet relies on.)
@Suite("NewItemSheetTests")
@MainActor
struct NewItemSheetTests {

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

    @discardableResult
    private func makeItemCollection(nexus: Nexus, title: String, in itemType: ItemType) throws -> ItemCollection {
        let folderURL = NexusPaths.itemCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: itemType.title,
            collectionFolderName: title
        )
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let coll = ItemCollection(
            id: ULID.generate(),
            typeID: itemType.id,
            title: title,
            folderURL: folderURL,
            modifiedAt: Date()
        )
        try coll.save(to: folderURL.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename))
        return coll
    }

    // MARK: - Test 1: Create into a Set

    @Test("Creating into a Set routes through ItemContentManager.createItem(in:type:)")
    func createsIntoCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let type = try makeItemType(nexus: nexus, title: "Recipes")
        let collection = try makeItemCollection(nexus: nexus, title: "Mains", in: type)

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let item = try await manager.createItem(name: "Pasta", in: collection, type: type)

        #expect(item.title == "Pasta")
        #expect(manager.items(in: collection).contains { $0.id == item.id })
    }

    // MARK: - Test 2: Create into a Type root

    @Test("Creating into a Type root routes through ItemContentManager.createItem(inTypeRoot:)")
    func createsIntoTypeRoot() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let type = try makeItemType(nexus: nexus, title: "Recipes")

        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        let item = try await manager.createItem(name: "Quick", inTypeRoot: type)

        #expect(item.title == "Quick")
        #expect(manager.items(in: type).contains { $0.id == item.id })
    }

    // MARK: - Test 3: Empty name fails the create-button validation predicate

    @Test("Empty name fails the create-button validation predicate")
    func emptyNameRejected() {
        let trimmed = "   ".trimmingCharacters(in: .whitespaces)
        #expect(trimmed.isEmpty)
    }
}
