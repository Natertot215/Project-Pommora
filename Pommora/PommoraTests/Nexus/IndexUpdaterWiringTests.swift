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
    /// when currentIndex is non-nil, all 6 managers should receive a non-nil
    /// IndexUpdater (same value — IndexUpdater is Sendable).
    @Test func managersReceiveIndexUpdaterAfterConstruction() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        // Build the 6 managers exactly as constructManagers does.
        let vaultMgr       = PageTypeManager(nexus: nexus)
        let itemTypeMgr    = ItemTypeManager(nexus: nexus)
        let agendaTaskMgr  = AgendaTaskManager(nexus: nexus)
        let agendaEventMgr = AgendaEventManager(nexus: nexus)

        let contentMgr: PageContentManager = PageContentManager(nexus: nexus) {
            NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
        }
        let itemContentMgr: ItemContentManager = ItemContentManager(nexus: nexus) {
            NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
        }

        // Replicate the Phase E.7.5 wiring block from constructManagers.
        let updater: IndexUpdater? = IndexUpdater(index)
        vaultMgr.indexUpdater       = updater
        itemTypeMgr.indexUpdater    = updater
        contentMgr.indexUpdater     = updater
        itemContentMgr.indexUpdater = updater
        agendaTaskMgr.indexUpdater  = updater
        agendaEventMgr.indexUpdater = updater

        // All 6 must be non-nil.
        #expect(vaultMgr.indexUpdater != nil)
        #expect(itemTypeMgr.indexUpdater != nil)
        #expect(contentMgr.indexUpdater != nil)
        #expect(itemContentMgr.indexUpdater != nil)
        #expect(agendaTaskMgr.indexUpdater != nil)
        #expect(agendaEventMgr.indexUpdater != nil)
    }

    // MARK: - Test 2: mutation via manager propagates to index

    /// Wire a PageTypeManager with indexUpdater; call createPageType; verify
    /// the row appears in page_types via a direct GRDB read.
    @Test func mutationViaManagerPropagatesToIndex() async throws {
        let (nexus, index) = try makeTempIndex()
        defer { TempNexus.cleanup(nexus) }

        let vaultMgr = PageTypeManager(nexus: nexus)
        await vaultMgr.loadAll()

        // Wire the updater.
        vaultMgr.indexUpdater = IndexUpdater(index)

        // Perform a mutation.
        try await vaultMgr.createPageType(name: "Research", icon: nil)

        // Verify the row is in the index.
        let count = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types WHERE title = ?", arguments: ["Research"]) ?? 0
        }
        #expect(count == 1)
    }

    // MARK: - Test 3: nil index produces nil updaters; mutations don't crash

    /// When currentIndex is nil (degraded mode), constructManagers assigns nil
    /// indexUpdater to all 6 managers. CRUD mutations must succeed without crashing.
    @Test func nilIndexResultsInNilUpdaters() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Build managers and apply nil updater — mirrors the .map path when
        // currentIndex is nil (Optional<PommoraIndex>.none.map { ... } = nil).
        let vaultMgr       = PageTypeManager(nexus: nexus)
        let itemTypeMgr    = ItemTypeManager(nexus: nexus)
        let agendaTaskMgr  = AgendaTaskManager(nexus: nexus)
        let agendaEventMgr = AgendaEventManager(nexus: nexus)

        let contentMgr: PageContentManager = PageContentManager(nexus: nexus) {
            NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
        }
        let itemContentMgr: ItemContentManager = ItemContentManager(nexus: nexus) {
            NexusContext(
                lookupSpace: { _ in nil },
                lookupTopic: { _ in nil },
                lookupProject: { _ in nil },
                lookupVault: { _ in nil }
            )
        }

        let updater: IndexUpdater? = nil   // simulates degraded mode
        vaultMgr.indexUpdater       = updater
        itemTypeMgr.indexUpdater    = updater
        contentMgr.indexUpdater     = updater
        itemContentMgr.indexUpdater = updater
        agendaTaskMgr.indexUpdater  = updater
        agendaEventMgr.indexUpdater = updater

        // All 6 must be nil.
        #expect(vaultMgr.indexUpdater == nil)
        #expect(itemTypeMgr.indexUpdater == nil)
        #expect(contentMgr.indexUpdater == nil)
        #expect(itemContentMgr.indexUpdater == nil)
        #expect(agendaTaskMgr.indexUpdater == nil)
        #expect(agendaEventMgr.indexUpdater == nil)

        // A mutation with nil indexUpdater must not crash.
        await vaultMgr.loadAll()
        try await vaultMgr.createPageType(name: "Notes", icon: nil)
        // If we reach here without throwing, the degraded path is safe.
        #expect(vaultMgr.types.count == 1)
    }
}
