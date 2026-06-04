import Foundation
import Testing

@testable import Pommora

/// Task 5.4 — `ItemTypeManager.clearTemplateConfig` sets a container's
/// `template_config` back to nil (NOT an empty config), so the resolver
/// falls back to the Type default for a Collection scope (LD-10). Mirror of
/// `UpdateTemplateConfigTests` setup (TempNexus + ItemTypeManager(nexus:) +
/// loadAll), all @MainActor.
@MainActor
@Suite("ClearTemplateConfig")
struct ClearTemplateConfigTests {

    @Test("clearTemplateConfig on a Collection nils its config; the resolver falls back to the Type")
    func clearCollectionFallsBackToType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        // Type default layout.
        try await manager.updateTemplateConfig(in: itemType.id) { $0.layout = .standard }

        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)
        let collectionID = manager.itemCollections(in: itemType).first!.id
        // Collection OWN override.
        try await manager.updateTemplateConfig(in: collectionID) { $0.layout = .gallery }
        #expect(manager.itemCollections(in: itemType).first?.templateConfig?.layout == .gallery)

        // Clear the Collection's own config → nil (not empty).
        try await manager.clearTemplateConfig(in: collectionID)

        let coll = manager.itemCollections(in: itemType).first!
        #expect(coll.templateConfig == nil)

        // The resolver now falls back to the Type default (LD-10).
        let type = manager.types.first!
        #expect(TemplateResolver.effective(type: type, collection: coll).layout == .standard)

        // Reload from disk confirms the Collection persisted as nil.
        let fresh = ItemTypeManager(nexus: nexus)
        await fresh.loadAll()
        let freshType = fresh.types.first!
        let freshColl = fresh.itemCollections(in: freshType).first!
        #expect(freshColl.templateConfig == nil)
        #expect(TemplateResolver.effective(type: freshType, collection: freshColl).layout == .standard)
    }

    @Test("clearTemplateConfig on a Collection that already has nil config is a safe no-op")
    func clearAlreadyNilIsNoOp() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)
        let collectionID = manager.itemCollections(in: itemType).first!.id
        #expect(manager.itemCollections(in: itemType).first?.templateConfig == nil)

        try await manager.clearTemplateConfig(in: collectionID)

        #expect(manager.itemCollections(in: itemType).first?.templateConfig == nil)
    }

    @Test("clearTemplateConfig throws typeNotFound when the container id matches nothing")
    func clearNotFound() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        await #expect(throws: ItemTypeManagerError.typeNotFound) {
            try await manager.clearTemplateConfig(in: "nonexistent")
        }
    }
}
