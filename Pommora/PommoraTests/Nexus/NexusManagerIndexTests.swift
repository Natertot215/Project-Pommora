//
//  NexusManagerIndexTests.swift
//  PommoraTests
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("NexusManagerIndex")
@MainActor
struct NexusManagerIndexTests {

    // MARK: - Fixture helpers

    /// Builds a pre-initialized nexus root (with `.nexus/nexus.json` already written).
    private func makeInitializedNexusRoot() throws -> (rootURL: URL, nexus: Nexus) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pommora-nm-index-\(UUID().uuidString)", isDirectory: true)
        let nexusDir = root.appendingPathComponent(".nexus", isDirectory: true)
        try FileManager.default.createDirectory(at: nexusDir, withIntermediateDirectories: true)
        let identity = NexusIdentity(id: ULID.generate())
        let identityURL = nexusDir.appendingPathComponent("nexus.json", isDirectory: false)
        try identity.save(to: identityURL)
        let nexus = Nexus(id: identity.id, rootURL: root)
        return (root, nexus)
    }

    // MARK: - Test 1: openExistingInitializesIndex

    /// Calling `openIndex(for:)` on a pre-initialized nexus folder sets
    /// `currentIndex` and materializes `index.db` on disk.
    @Test func openExistingInitializesIndex() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = NexusManager()
        await manager.openIndex(for: nexus)

        #expect(manager.currentIndex != nil)
        let dbPath = root.appendingPathComponent(".nexus/index.db").path
        #expect(FileManager.default.fileExists(atPath: dbPath))
    }

    // MARK: - Test 2: openPickedInitializesAndPopulates

    /// A fresh nexus (no prior index.db) triggers `IndexBuilder.populate`.
    /// After `openIndex`, the index tables exist and a seeded PageCollection appears.
    @Test func openPickedInitializesAndPopulates() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Seed one PageCollection so populate has something to write.
        let ptManager = PageCollectionManager(nexus: nexus)
        await ptManager.loadAll()
        try await ptManager.createPageCollection(name: "Notes", icon: nil)

        let manager = NexusManager()
        await manager.openIndex(for: nexus)

        #expect(manager.currentIndex != nil)
        guard let idx = manager.currentIndex else { return }

        // Fresh open always triggers populate (needsRebuild == true on new DB).
        let ptCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1
        }
        #expect(ptCount == 1)
    }

    // MARK: - Test 3: indexInitFailureLeavesNexusUsable

    /// When the nexus root itself is unwritable, `PommoraIndex.open` cannot create
    /// the `.nexus` dir and throws. `openIndex` must surface `.initFailed` and
    /// leave `currentIndex == nil`, while any previously-set `currentNexus` is
    /// unaffected.
    @Test func indexInitFailureLeavesNexusUsable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pommora-nm-failtest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Restore write permissions so cleanup works.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }

        // Use a fake nexus that points at a read-only root with NO .nexus subdir.
        // PommoraIndex.open will try to createDirectory(at:.nexus) and fail.
        let nexus = Nexus(id: ULID.generate(), rootURL: root)

        // Lock down the root so createDirectory fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        let manager = NexusManager()
        manager.currentNexus = nexus  // simulate nexus already set
        await manager.openIndex(for: nexus)

        // Index must be nil on failure.
        #expect(manager.currentIndex == nil)
        // Nexus must still be set (wasn't touched by openIndex).
        #expect(manager.currentNexus != nil)
        // A .initFailed error must be surfaced.
        if case .initFailed(let msg) = manager.pendingError {
            #expect(msg.hasPrefix("Index init failed:"))
        } else {
            Issue.record("Expected .initFailed error; got \(String(describing: manager.pendingError))")
        }
    }

    // MARK: - Test 4: resetBookmarkClearsIndex

    /// `resetBookmark()` (DEBUG-only) must clear both `currentNexus` and `currentIndex`.
    #if DEBUG
    @Test func resetBookmarkClearsIndex() async throws {
        let (root, nexus) = try makeInitializedNexusRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = NexusManager()
        await manager.openIndex(for: nexus)
        manager.currentNexus = nexus

        #expect(manager.currentIndex != nil)
        #expect(manager.currentNexus != nil)

        manager.resetBookmark()

        #expect(manager.currentIndex == nil)
        #expect(manager.currentNexus == nil)
    }
    #endif
}
