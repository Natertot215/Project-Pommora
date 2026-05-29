import Foundation
import Testing
@testable import Pommora

@Suite("BuiltInRelationProperties") struct BuiltInRelationPropertiesTests {
    private let defaultTierConfig = TierConfig.defaultSeed()

    @Test func mergeAppendsThreeTierEntriesWhenNoneInSidecar() {
        let result = BuiltInRelationProperties.merge(
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
        let result = BuiltInRelationProperties.merge(
            existing: [sidecarTier1],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let merged = result.first { $0.id == ReservedPropertyID.tier1 }
        #expect(merged?.name == "Library Branches")
        #expect(merged?.icon == "books.vertical")
    }

    @Test func mergeUsesTierConfigDefaultWhenSidecarNameAbsent() {
        let result = BuiltInRelationProperties.merge(
            existing: [],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let tier1 = result.first { $0.id == ReservedPropertyID.tier1 }
        // TierConfig.defaultSeed() level 1 plural == "Spaces"
        #expect(tier1?.name == "Spaces")
    }

    @Test func mergeUsesHardcodedFallbackIconsWhenSidecarAbsent() {
        let result = BuiltInRelationProperties.merge(
            existing: [],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let tier1 = result.first { $0.id == ReservedPropertyID.tier1 }
        let tier2 = result.first { $0.id == ReservedPropertyID.tier2 }
        let tier3 = result.first { $0.id == ReservedPropertyID.tier3 }
        #expect(tier1?.icon == "building.2")
        #expect(tier2?.icon == "tag")
        #expect(tier3?.icon == "briefcase")
    }

    @Test func mergeIgnoresStructurallyLockedRelationScopeInSidecar() {
        let tamperedTier1 = PropertyDefinition(
            id: ReservedPropertyID.tier1,
            name: "Spaces",
            type: .relation,
            relationScope: .pageType("tampered")
        )
        let result = BuiltInRelationProperties.merge(
            existing: [tamperedTier1],
            tierConfig: defaultTierConfig,
            sourceTypeID: "type_test"
        )
        let tier1 = result.first { $0.id == ReservedPropertyID.tier1 }
        #expect(tier1?.relationScope == .contextTier(1))
    }
}
