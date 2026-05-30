import Foundation
import Testing

@testable import Pommora

/// F3 (RED): Tests for `DualRelationCoordinator.updatePairedRelation` —
/// updating both sides of a paired relation atomically.
///
/// All tests operate on a temp nexus (filesystem real writes) to exercise the
/// full SchemaTransaction commit path.
@Suite("PairedRelationUpdateTests")
struct PairedRelationUpdateTests {

    // MARK: - Helpers (mirrored from DualRelationCoordinatorTests)

    /// Creates a PageType on disk and returns it.
    @discardableResult
    private static func makePageType(
        id: String = ULID.generate(),
        title: String,
        nexus: Nexus
    ) throws -> PageType {
        let pt = PageType(
            id: id,
            title: title,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: title, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: pt)
        return pt
    }

    /// Creates an ItemType on disk and returns it.
    @discardableResult
    private static func makeItemType(
        id: String = ULID.generate(),
        title: String,
        nexus: Nexus
    ) throws -> ItemType {
        let it = ItemType(
            id: id,
            title: title,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: it)
        return it
    }

    /// Reloads a PageType from its sidecar.
    private static func reloadPageType(_ title: String, nexus: Nexus) throws -> PageType {
        let meta = NexusPaths.vaultMetadataURL(forTitle: title, in: nexus)
        return try PageType.load(from: meta)
    }

    /// Reloads an ItemType from its sidecar.
    private static func reloadItemType(_ title: String, nexus: Nexus) throws -> ItemType {
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
        return try ItemType.load(from: meta)
    }

    // MARK: - F3.1: updatePairedRelation updates both sides

    @Test("updatePairedRelationUpdatesBothSides — new home and reverse name+icon written to both sidecars")
    func updatePairedRelationUpdatesBothSides() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeA = try Self.makePageType(title: "TypeA", nexus: nexus)
        let typeB = try Self.makeItemType(title: "TypeB", nexus: nexus)

        // Create the initial paired relation (source: "Tasks"/"list" on TypeA;
        // target: "Project"/"folder" on TypeB).
        let (sourceID, targetID) = try DualRelationCoordinator.createPairedRelation(
            source: .pageType(typeA),
            sourcePropertyName: "Tasks",
            sourceScope: .itemType(typeB.id),
            target: .itemType(typeB),
            targetPropertyName: "Project",
            targetScope: .pageType(typeA.id),
            sourceIcon: "list",
            targetIcon: "folder",
            nexus: nexus
        )

        // Reload both types so we have the current in-memory state with dualProperty
        // configs intact — required before calling updatePairedRelation.
        let updatedTypeA = try Self.reloadPageType("TypeA", nexus: nexus)
        let updatedTypeB = try Self.reloadItemType("TypeB", nexus: nexus)

        // Update both sides: home → "Action Items"/"checklist", reverse → "Parent"/"folder.badge.gearshape".
        try DualRelationCoordinator.updatePairedRelation(
            sourcePropertyID: sourceID,
            sourceKind: .pageType(updatedTypeA),
            targetKind: .itemType(updatedTypeB),
            newHomeName: "Action Items",
            newHomeIcon: "checklist",
            newReverseName: "Parent",
            newReverseIcon: "folder.badge.gearshape",
            nexus: nexus
        )

        // Reload BOTH sidecars from disk and verify.
        let reloadedTypeA = try Self.reloadPageType("TypeA", nexus: nexus)
        let reloadedTypeB = try Self.reloadItemType("TypeB", nexus: nexus)

        let sourceProp = reloadedTypeA.properties.first { $0.id == sourceID }
        let targetProp = reloadedTypeB.properties.first { $0.id == targetID }

        // Source (home) side assertions.
        #expect(sourceProp?.name == "Action Items")
        #expect(sourceProp?.icon == "checklist")

        // Target (reverse) side assertions.
        #expect(targetProp?.name == "Parent")
        #expect(targetProp?.icon == "folder.badge.gearshape")
    }
}
