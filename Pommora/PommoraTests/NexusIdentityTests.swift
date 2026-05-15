//
//  NexusIdentityTests.swift
//  PommoraTests
//

import Foundation
import Testing
@testable import Pommora

struct NexusIdentityTests {
    @Test func defaultInitializerSetsSchemaVersion1AndCurrentDate() {
        let now = Date.now
        let identity = NexusIdentity(id: "01HXX")
        #expect(identity.schemaVersion == 1)
        #expect(identity.id == "01HXX")
        // createdAt should be within a second of now
        #expect(abs(identity.createdAt.timeIntervalSince(now)) < 1.0)
    }

    @Test func roundTripPreservesAllFields() throws {
        let original = NexusIdentity(
            schemaVersion: 1,
            id: ULID.generate(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try original.save(to: url)
        let loaded = try NexusIdentity.load(from: url)

        #expect(loaded.schemaVersion == original.schemaVersion)
        #expect(loaded.id == original.id)
        #expect(loaded.createdAt == original.createdAt)
    }

    @Test func savedJSONUsesISO8601Date() throws {
        let identity = NexusIdentity(
            id: "01HXX",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try identity.save(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        // ISO-8601 representation of 2023-11-14T22:13:20Z
        #expect(raw.contains("2023-11-14T22:13:20Z"))
    }

    private func uniqueTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusIdentityTests-\(UUID().uuidString).json")
    }
}
