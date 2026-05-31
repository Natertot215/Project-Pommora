//
//  RelationDeleteToleranceTests.swift
//  PommoraTests
//
//  RED baseline (fails against pre-fix code).
//
//  Bug pinned: deleting a PAIRED (dual) relation property whose `relationTarget`
//  is a LEGACY collection scope (`.pageCollection` / `.itemCollection`) threw
//  `PageTypeManagerError.propertyNotFound` (bridged as "Pommora.PageTypeManager
//  Error error 1"). Cause: the dual branch in `deleteProperty` called
//  `try resolveDualTargetKind(for: scope)`, which throws for collection targets,
//  aborting the whole delete before the owner-side property was removed. The
//  error then rendered RAW because the manager error enums lacked `LocalizedError`.
//
//  Intended fix: the reverse cascade becomes best-effort (`try?`); on an
//  unresolvable reverse the delete falls through to the owner-only removal so the
//  owner property is ALWAYS deletable. The error enums conform to `LocalizedError`
//  so any surfaced text is a friendly sentence (no type name / "error N").
//
//  Operates on a temp nexus (real filesystem writes), mirroring the harness in
//  `CollectionTypeIDReconcileTests` + `PairedRelationManagerUpdateTests`.
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("RelationDeleteToleranceTests")
struct RelationDeleteToleranceTests {

    // MARK: - Page side

    /// A PageType carries a paired relation property whose `relationTarget` is a
    /// legacy `.pageCollection`. Deleting it must NOT throw (the reverse cascade is
    /// skipped), the property must be gone, and `pendingError` must stay nil.
    @Test func deletingPairedRelationWithLegacyCollectionTargetDoesNotThrow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Hoist all ULID mints BEFORE building the entity (Swift 6 @Sendable).
        let vaultID = ULID.generate()
        let propID = ReservedPropertyID.mintUserPropertyID()
        let legacyCollID = ULID.generate()
        let syncedPropID = ReservedPropertyID.mintUserPropertyID()
        let syncedTypeID = ULID.generate()

        let vaultName = "Legacy Page Vault"
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: vaultName, in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)

        // Paired relation whose target is a LEGACY collection scope — the exact
        // shape that aborted the delete pre-fix.
        let relationProp = PropertyDefinition(
            id: propID,
            name: "Linked",
            type: .relation,
            icon: "link",
            relationTarget: .pageCollection(legacyCollID),
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: syncedPropID,
                syncedPropertyDefinedOnTypeID: syncedTypeID
            )
        )
        let pageType = PageType(
            id: vaultID,
            title: vaultName,
            icon: nil,
            properties: [relationProp],
            views: [],
            modifiedAt: Date()
        )
        try pageType.save(to: vaultFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        let loaded = try #require(manager.types.first(where: { $0.id == vaultID }))
        #expect(loaded.properties.contains(where: { $0.id == propID }))

        // The delete must succeed (no throw) despite the unresolvable reverse.
        try await manager.deleteProperty(id: propID, in: vaultID)

        // Owner property is gone, and nothing latched a pending error.
        let after = try #require(manager.types.first(where: { $0.id == vaultID }))
        #expect(!after.properties.contains(where: { $0.id == propID }))
        #expect(manager.pendingError == nil)
    }

    // MARK: - Item side (symmetric)

    /// Mirror of the page-side case: an ItemType with a paired relation targeting
    /// a legacy `.itemCollection`. Delete must not throw, property gone, no pending error.
    @Test func deletingPairedItemRelationWithLegacyCollectionTargetDoesNotThrow() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let typeID = ULID.generate()
        let propID = ReservedPropertyID.mintUserPropertyID()
        let legacyCollID = ULID.generate()
        let syncedPropID = ReservedPropertyID.mintUserPropertyID()
        let syncedTypeID = ULID.generate()

        let typeName = "Legacy Item Type"
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: typeName)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)

        let relationProp = PropertyDefinition(
            id: propID,
            name: "Linked",
            type: .relation,
            icon: "link",
            relationTarget: .itemCollection(legacyCollID),
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: syncedPropID,
                syncedPropertyDefinedOnTypeID: syncedTypeID
            )
        )
        let itemType = ItemType(
            id: typeID,
            title: typeName,
            icon: nil,
            properties: [relationProp],
            views: [],
            modifiedAt: Date()
        )
        try itemType.save(to: typeFolder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename))

        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()

        let loaded = try #require(manager.types.first(where: { $0.id == typeID }))
        #expect(loaded.properties.contains(where: { $0.id == propID }))

        try await manager.deleteProperty(id: propID, in: typeID)

        let after = try #require(manager.types.first(where: { $0.id == typeID }))
        #expect(!after.properties.contains(where: { $0.id == propID }))
        #expect(manager.pendingError == nil)
    }

    // MARK: - Friendly error rendering (LocalizedError conformance)

    /// `.localizedDescription` must NOT contain the raw type name. Pre-fix the
    /// bridged string is "Pommora.PageTypeManagerError error 1"; post-fix the
    /// `LocalizedError.errorDescription` text replaces it.
    @Test func pageTypeManagerErrorRendersFriendly() {
        #expect(!PageTypeManagerError.propertyNotFound.localizedDescription.contains("PageTypeManagerError"))
    }

    /// Item-side mirror of the friendly-error assertion.
    @Test func itemTypeManagerErrorRendersFriendly() {
        #expect(!ItemTypeManagerError.propertyNotFound.localizedDescription.contains("ItemTypeManagerError"))
    }
}
