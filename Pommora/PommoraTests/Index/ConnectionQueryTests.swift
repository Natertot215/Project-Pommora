import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("ConnectionQueryTests")
@MainActor
struct ConnectionQueryTests {

    // MARK: - Helpers

    private func makeIndex(at nexus: Nexus) throws -> PommoraIndex {
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return idx
    }

    /// Insert a page row (with its required page_type parent).
    private func insertPage(id: String, title: String, index: PommoraIndex) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = iso.string(from: Date())
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_types (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["pt-test", "TestVault", now])
            try db.execute(
                sql: "INSERT INTO pages (id, page_type_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [id, "pt-test", title, now])
        }
    }

    // MARK: - Test 1: outgoing/incoming/resolved

    @Test func outgoingIncomingAndResolved() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let updater = IndexUpdater(idx)
        let query = IndexQuery(idx)

        let targetID = ULID.generate()
        try insertPage(id: targetID, title: "Target", index: idx)

        try updater.reconcileConnections(
            sourceID: "S",
            sourceKind: "page",
            sourceTitle: "Source",
            body: "[[Target]] [[Ghost]]"
        )

        // Outgoing: 2 edges from "S" (one resolved, one phantom)
        let outgoing = try await query.outgoingConnections(sourceID: "S")
        #expect(outgoing.count == 2)

        let resolvedEdge = outgoing.first { $0.resolved }
        #expect(resolvedEdge != nil)
        #expect(resolvedEdge?.targetID == targetID)
        #expect(resolvedEdge?.targetTitle == "target")
        #expect(resolvedEdge?.sourceKind == .page)

        let phantomEdge = outgoing.first { !$0.resolved }
        #expect(phantomEdge != nil)
        #expect(phantomEdge?.targetID == nil)
        #expect(phantomEdge?.targetTitle == "ghost")

        // Incoming: only the resolved edge points at targetID
        let incoming = try await query.incomingConnections(targetID: targetID)
        #expect(incoming.count == 1)
        #expect(incoming[0].sourceID == "S")
        #expect(incoming[0].resolved == true)
        #expect(incoming[0].targetID == targetID)
    }

    // MARK: - Test 2: titleExists

    @Test func titleExists() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let query = IndexQuery(idx)

        let targetID = ULID.generate()
        try insertPage(id: targetID, title: "Target", index: idx)

        // Case-insensitive match returns true
        let exists = try await query.titleExists("target")
        #expect(exists == true)

        // Non-existent title returns false
        let missing = try await query.titleExists("nope")
        #expect(missing == false)

        // Excluding the only holder returns false
        let excludedSelf = try await query.titleExists("Target", excludingID: targetID)
        #expect(excludedSelf == false)
    }

    // MARK: - Test 3: titleCandidates

    @Test func titleCandidatesPrefixMatch() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let idx = try makeIndex(at: nexus)
        let query = IndexQuery(idx)

        let appleID = ULID.generate()
        let apricotID = ULID.generate()
        let bananaID = ULID.generate()
        try insertPage(id: appleID, title: "Apple", index: idx)
        try insertPage(id: apricotID, title: "Apricot", index: idx)
        try insertPage(id: bananaID, title: "Banana", index: idx)

        let candidates = try await query.titleCandidates(matching: "Ap")
        #expect(candidates.count == 2)
        let ids = Set(candidates.map(\.id))
        #expect(ids == [appleID, apricotID])
        #expect(!ids.contains(bananaID))
    }
}
