//
//  IndexUpdaterWiringTests.swift
//  PommoraTests
//

import Foundation
import GRDB
import Testing

@testable import Pommora

// MARK: - Helpers

/// Builds a PommoraIndex at a temp nexus root and returns both.
private func makeTempIndex() throws -> (nexus: Nexus, index: PommoraIndex) {
    let nexus = try TempNexus.make()
    let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
    return (nexus, index)
}

// MARK: - Suite

@Suite("IndexUpdater wiring")
@MainActor
struct IndexUpdaterWiringTests {

    // MARK: - Test 1: managers receive non-nil indexUpdater when index is non-nil

    /// Mirrors the ContentView.constructManagers assignment block:
    /// when currentIndex is non-nil, all 4 managers should receive a non-nil
    /// IndexUpdater (same value — IndexUpdater is Sendable).
    @Test func managersReceiveIndexUpdaterAfterConstruction() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        // Build the 4 managers exactly as constructManagers does.
        let vaultMgr = PageCollectionManager(nexus: nexus)
        let agendaTaskMgr = AgendaTaskManager(nexus: nexus)
        let agendaEventMgr = AgendaEventManager(nexus: nexus)

        let contentMgr: PageContentManager = PageContentManager(nexus: nexus) {
            NexusContext(
                lookupArea: { _ in nil },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
        }

        // Replicate the Phase E.7.5 wiring block from constructManagers.
        let updater: IndexUpdater? = IndexUpdater(index)
        vaultMgr.indexUpdater = updater
        contentMgr.indexUpdater = updater
        agendaTaskMgr.indexUpdater = updater
        agendaEventMgr.indexUpdater = updater

        #expect(vaultMgr.indexUpdater != nil)
        #expect(contentMgr.indexUpdater != nil)
        #expect(agendaTaskMgr.indexUpdater != nil)
        #expect(agendaEventMgr.indexUpdater != nil)
    }

    // MARK: - Test 2: mutation via manager propagates to index

    /// Wire a PageCollectionManager with indexUpdater; call createPageCollection; verify
    /// the row appears in page_collections via a direct GRDB read.
    @Test func mutationViaManagerPropagatesToIndex() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        let vaultMgr = PageCollectionManager(nexus: nexus)
        await vaultMgr.loadAll()

        vaultMgr.indexUpdater = IndexUpdater(index)

        try await vaultMgr.createPageCollection(name: "Research", icon: nil)

        let count = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections WHERE title = ?", arguments: ["Research"]) ?? 0
        }
        #expect(count == 1)
    }

    // MARK: - Test 3: nil index produces nil updaters; mutations don't crash

    /// When currentIndex is nil (degraded mode), constructManagers assigns nil
    /// indexUpdater to all 4 managers. CRUD mutations must succeed without crashing.
    @Test func nilIndexResultsInNilUpdaters() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Build managers and apply nil updater — mirrors the .map path when
        // currentIndex is nil (Optional<PommoraIndex>.none.map { ... } = nil).
        let vaultMgr = PageCollectionManager(nexus: nexus)
        let agendaTaskMgr = AgendaTaskManager(nexus: nexus)
        let agendaEventMgr = AgendaEventManager(nexus: nexus)

        let contentMgr: PageContentManager = PageContentManager(nexus: nexus) {
            NexusContext(
                lookupArea: { _ in nil },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
        }

        let updater: IndexUpdater? = nil  // simulates degraded mode
        vaultMgr.indexUpdater = updater
        contentMgr.indexUpdater = updater
        agendaTaskMgr.indexUpdater = updater
        agendaEventMgr.indexUpdater = updater

        #expect(vaultMgr.indexUpdater == nil)
        #expect(contentMgr.indexUpdater == nil)
        #expect(agendaTaskMgr.indexUpdater == nil)
        #expect(agendaEventMgr.indexUpdater == nil)

        // A mutation with nil indexUpdater must not crash.
        await vaultMgr.loadAll()
        try await vaultMgr.createPageCollection(name: "Notes", icon: nil)
        // If we reach here without throwing, the degraded path is safe.
        #expect(vaultMgr.types.count == 1)
    }

    // MARK: - Test 4: deleteProperty removes the property_definitions row (PageCollectionManager)

    /// Wire a real IndexUpdater into a PageCollectionManager; add a user property so a
    /// `property_definitions` row is written; call `deleteProperty(id:in:)`; assert
    /// the row is gone from the index. Pins the invariant that `deleteProperty`
    /// always calls `indexUpdater.deletePropertyDefinition(id:)`.
    @Test func deletePropertyRemovesIndexRow_pageType() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        let vaultMgr = PageCollectionManager(nexus: nexus)
        await vaultMgr.loadAll()
        vaultMgr.indexUpdater = IndexUpdater(index)

        // Create a PageCollection so we have a typeID to operate on.
        try await vaultMgr.createPageCollection(name: "Journal", icon: nil)
        guard let pageCollection = vaultMgr.types.first else {
            Issue.record("Expected at least one page type after createPageCollection")
            return
        }

        // Add a user property — this writes a property_definitions row via upsert.
        let propID = ReservedPropertyID.mintUserPropertyID()
        let def = PropertyDefinition(id: propID, name: "Priority", type: .number)
        try await vaultMgr.addProperty(def, to: pageCollection.id)

        // Confirm the row exists in the index before deletion.
        let countBefore = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM property_definitions WHERE id = ?",
                arguments: [propID]
            ) ?? 0
        }
        #expect(countBefore == 1, "property_definitions row must exist after addProperty")

        // Delete the property — must call indexUpdater.deletePropertyDefinition(id:).
        try await vaultMgr.deleteProperty(id: propID, in: pageCollection.id)

        // Assert the row is gone.
        let countAfter = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM property_definitions WHERE id = ?",
                arguments: [propID]
            ) ?? 0
        }
        #expect(countAfter == 0, "property_definitions row must be absent after deleteProperty")
    }

    // MARK: - Test 5: reorderProperty updates positions in the index (PageCollectionManager)

    /// Wire a real IndexUpdater into a PageCollectionManager; add two user properties so
    /// two `property_definitions` rows are written with their initial positions; call
    /// `reorderProperty` to swap their order; assert both rows reflect the new
    /// positions in the index.
    ///
    /// **Key finding:** `reorderProperty` calls `upsertPropertyDefinition` for every
    /// property in the schema with its new `position` value — so the index is updated
    /// on every reorder, not skipped.
    @Test func reorderPropertyUpdatesPositionsInIndex_pageType() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        let vaultMgr = PageCollectionManager(nexus: nexus)
        await vaultMgr.loadAll()
        vaultMgr.indexUpdater = IndexUpdater(index)

        try await vaultMgr.createPageCollection(name: "Notes", icon: nil)
        guard let pageCollection = vaultMgr.types.first else {
            Issue.record("Expected at least one page type after createPageCollection")
            return
        }

        // Add two user properties — each addProperty call upserts a row with position.
        let propAID = ReservedPropertyID.mintUserPropertyID()
        let propBID = ReservedPropertyID.mintUserPropertyID()
        try await vaultMgr.addProperty(
            PropertyDefinition(id: propAID, name: "Alpha", type: .number), to: pageCollection.id)
        try await vaultMgr.addProperty(
            PropertyDefinition(id: propBID, name: "Beta", type: .number), to: pageCollection.id)

        // Reload the manager's in-memory type to get the true ordering and index.
        guard let typeAfterAdd = vaultMgr.types.first(where: { $0.id == pageCollection.id }) else {
            Issue.record("PageCollection missing after addProperty calls")
            return
        }
        guard let posABefore = typeAfterAdd.properties.firstIndex(where: { $0.id == propAID }),
            let posBBefore = typeAfterAdd.properties.firstIndex(where: { $0.id == propBID })
        else {
            Issue.record("Added properties not found in type after addProperty")
            return
        }
        // Both props are present; Alpha was added first so it precedes Beta.
        #expect(posABefore < posBBefore, "Alpha should precede Beta after sequential addProperty")

        // Move Beta before Alpha (toIndex = posABefore moves Beta to Alpha's slot).
        try await vaultMgr.reorderProperty(id: propBID, in: pageCollection.id, toIndex: posABefore)

        // Read positions from the index for both properties.
        let posAInIndex = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT position FROM property_definitions WHERE id = ?",
                arguments: [propAID]
            )
        }
        let posBInIndex = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT position FROM property_definitions WHERE id = ?",
                arguments: [propBID]
            )
        }

        // After reorder, Beta's index position must be less than Alpha's.
        guard let pA = posAInIndex, let pB = posBInIndex else {
            Issue.record("property_definitions rows missing after reorderProperty")
            return
        }
        #expect(pB < pA, "Beta's index position must be less than Alpha's after reorder")
    }

    // MARK: - Test 6: deleteProperty removes the property_definitions row (AgendaTaskManager)

    /// Wire a real IndexUpdater into an AgendaTaskManager; add a user property so a
    /// `property_definitions` row is written; call `deleteProperty(id:)`; assert the
    /// row is gone. Pins the singleton-manager variant of the same contract.
    @Test func deletePropertyRemovesIndexRow_agendaTask() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        let taskMgr = AgendaTaskManager(nexus: nexus)
        await taskMgr.loadAll()
        taskMgr.indexUpdater = IndexUpdater(index)

        // Add a user property — this writes a property_definitions row.
        let propID = ReservedPropertyID.mintUserPropertyID()
        let def = PropertyDefinition(id: propID, name: "Context", type: .number)
        try await taskMgr.addProperty(def)

        // Confirm the row exists.
        let countBefore = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM property_definitions WHERE id = ?",
                arguments: [propID]
            ) ?? 0
        }
        #expect(countBefore == 1, "property_definitions row must exist after addProperty")

        // Delete the property.
        try await taskMgr.deleteProperty(id: propID)

        // Assert the row is gone.
        let countAfter = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM property_definitions WHERE id = ?",
                arguments: [propID]
            ) ?? 0
        }
        #expect(countAfter == 0, "property_definitions row must be absent after deleteProperty")
    }

    // MARK: - Test 7: reorderProperty updates positions in the index (AgendaTaskManager)

    /// Wire a real IndexUpdater into an AgendaTaskManager; add two user properties;
    /// call `reorderProperty` to move the second before the first; assert the index
    /// reflects the new positions.
    ///
    /// Note: the default seed contains `_status` at position 0. Added user properties
    /// follow it. The test adds two user props and moves the later one before the earlier.
    @Test func reorderPropertyUpdatesPositionsInIndex_agendaTask() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        let taskMgr = AgendaTaskManager(nexus: nexus)
        await taskMgr.loadAll()
        taskMgr.indexUpdater = IndexUpdater(index)

        // Add two user properties sequentially.
        let propAID = ReservedPropertyID.mintUserPropertyID()
        let propBID = ReservedPropertyID.mintUserPropertyID()
        try await taskMgr.addProperty(PropertyDefinition(id: propAID, name: "TagA", type: .number))
        try await taskMgr.addProperty(PropertyDefinition(id: propBID, name: "TagB", type: .number))

        // Determine Alpha's in-memory position (the slot we'll move Beta to).
        guard let posABefore = taskMgr.schema.properties.firstIndex(where: { $0.id == propAID })
        else {
            Issue.record("PropA not found in schema after addProperty")
            return
        }

        // Move Beta to Alpha's position (before Alpha).
        try await taskMgr.reorderProperty(id: propBID, toIndex: posABefore)

        // Read positions from the index.
        let posAInIndex = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT position FROM property_definitions WHERE id = ?",
                arguments: [propAID]
            )
        }
        let posBInIndex = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT position FROM property_definitions WHERE id = ?",
                arguments: [propBID]
            )
        }

        guard let pA = posAInIndex, let pB = posBInIndex else {
            Issue.record("property_definitions rows missing after reorderProperty")
            return
        }
        #expect(pB < pA, "Beta's index position must be less than Alpha's after reorder")
    }
}
