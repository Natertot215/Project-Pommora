import Foundation
import Testing

@testable import Pommora

@Suite("BuiltInContextLinkProperties") struct BuiltInContextLinkPropertiesTests {
    private let defaultTierConfig = TierConfig.defaultSeed()

    @Test func mergeAppendsThreeTierEntriesWhenNoneInSidecar() {
        let result = BuiltInContextLinkProperties.merge(
            existing: [],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        #expect(result.count == 3)
        #expect(result.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(result.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(result.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test func mergeHonorsSidecarDisplayNameOverride() {
        let sidecarTier1 = PropertyDefinition(
            id: ReservedPropertyID.tier1,
            name: "Library Branches",
            type: .relation,
            icon: "books.vertical"
        )
        let result = BuiltInContextLinkProperties.merge(
            existing: [sidecarTier1],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let merged = result.first { $0.id == ReservedPropertyID.tier1 }
        #expect(merged?.name == "Library Branches")
        #expect(merged?.icon == "books.vertical")
    }

    @Test func mergeUsesTierConfigDefaultWhenSidecarNameAbsent() {
        let result = BuiltInContextLinkProperties.merge(
            existing: [],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let tier1 = result.first { $0.id == ReservedPropertyID.tier1 }
        // TierConfig.defaultSeed() level 1 plural == "Areas"
        #expect(tier1?.name == "Areas")
    }

    @Test func mergeUsesHardcodedFallbackIconsWhenSidecarAbsent() {
        let result = BuiltInContextLinkProperties.merge(
            existing: [],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let tier1 = result.first { $0.id == ReservedPropertyID.tier1 }
        let tier2 = result.first { $0.id == ReservedPropertyID.tier2 }
        let tier3 = result.first { $0.id == ReservedPropertyID.tier3 }
        #expect(tier1?.icon == "square.grid.2x2")
        #expect(tier2?.icon == "square.grid.2x2")
        #expect(tier3?.icon == "square.grid.2x2")
    }

    @Test func mergeIgnoresStructurallyLockedRelationTargetInSidecar() {
        // A sidecar _tier1 entry with a wrong tier number must be overridden by merge
        // to the structurally correct .contextTier(1). The on-disk target is never
        // trusted for reserved tier IDs.
        let tamperedTier1 = PropertyDefinition(
            id: ReservedPropertyID.tier1,
            name: "Areas",
            type: .relation,
            relationTarget: .contextTier(99)
        )
        let result = BuiltInContextLinkProperties.merge(
            existing: [tamperedTier1],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let tier1 = result.first { $0.id == ReservedPropertyID.tier1 }
        #expect(tier1?.relationTarget == .contextTier(1))
    }
}
