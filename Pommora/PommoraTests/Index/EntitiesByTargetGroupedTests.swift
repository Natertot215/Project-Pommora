//
//  EntitiesByTargetGroupedTests.swift
//  PommoraTests
//
//  Task 4a — `IndexQuery.entitiesByContextTargetGrouped`: the grouped data feed for the
//  relation value picker. Post-Relations-redesign: only `.contextTier` survives;
//  the per-Type grouped paths are retired.
//
//  Struct name MATCHES the filename (quirk #18).
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("EntitiesByTargetGroupedTests")
struct EntitiesByTargetGroupedTests {

    @Test func contextTierScopeReturnsFlatNoGroups() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let spaceID = ULID.generate()
        try updater.upsertContext(
            Space(id: spaceID, title: "Personal", color: nil, icon: "person", blocks: [], modifiedAt: Date())
        )

        let grouped = try await IndexQuery(index).entitiesByContextTargetGrouped(.contextTier(1))

        // Context-tier scope → flat: no groups; the Space lands in rootEntities.
        #expect(grouped.groups.isEmpty)
        #expect(grouped.rootEntities.contains { $0.id == spaceID })
    }
}
