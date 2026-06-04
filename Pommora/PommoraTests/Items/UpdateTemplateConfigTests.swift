import Foundation
import Testing

@testable import Pommora

/// Task 2.4 — `ItemTypeManager.updateTemplateConfig` is the single template-persist
/// path (the ONLY writer of `template_config`). Mirrors `updateView`'s two-branch
/// container lookup (ItemType first, then ItemCollection) + in-memory cache
/// write-back + disk persist. Setup mirrors ItemTypeManagerTests (TempNexus +
/// ItemTypeManager(nexus:) + loadAll), all @MainActor.
@MainActor
@Suite("UpdateTemplateConfig")
struct UpdateTemplateConfigTests {

    @Test("updateTemplateConfig on a Type seeds-if-nil, writes back in-memory, and persists")
    func updateTemplateConfigOnType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let typeID = manager.types.first!.id
        #expect(manager.types.first?.templateConfig == nil)

        try await manager.updateTemplateConfig(in: typeID) { $0.layout = .gallery }

        // In-memory cache reflects the change immediately (no reload).
        #expect(manager.types.first?.templateConfig?.layout == .gallery)
        #expect(manager.types.first { $0.id == typeID }?.templateConfig?.layout == .gallery)

        // Reload from disk also shows the change (persisted).
        let fresh = ItemTypeManager(nexus: nexus)
        await fresh.loadAll()
        #expect(fresh.types.first?.templateConfig?.layout == .gallery)
    }

    @Test("updateTemplateConfig on a Collection writes that Collection's cache; the Type is untouched")
    func updateTemplateConfigOnCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createItemType(name: "Errands", icon: nil)
        let itemType = manager.types.first!
        try await manager.createItemCollection(name: "Groceries", inItemType: itemType)
        let collectionID = manager.itemCollections(in: itemType).first!.id

        try await manager.updateTemplateConfig(in: collectionID) { $0.layout = .compact }

        // The Collection's cached templateConfig reflects the change immediately.
        let coll = manager.itemCollections(in: itemType).first!
        #expect(coll.templateConfig?.layout == .compact)

        // The parent Type's own templateConfig is unchanged (still nil).
        #expect(manager.types.first?.templateConfig == nil)

        // Reload from disk confirms the Collection persisted + Type stayed nil.
        let fresh = ItemTypeManager(nexus: nexus)
        await fresh.loadAll()
        let freshType = fresh.types.first!
        #expect(fresh.itemCollections(in: freshType).first?.templateConfig?.layout == .compact)
        #expect(freshType.templateConfig == nil)
    }

    @Test("updateTemplateConfig throws typeNotFound when the container id matches nothing")
    func updateTemplateConfigNotFound() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        await #expect(throws: ItemTypeManagerError.typeNotFound) {
            try await manager.updateTemplateConfig(in: "nonexistent") { $0.layout = .gallery }
        }
    }
}
