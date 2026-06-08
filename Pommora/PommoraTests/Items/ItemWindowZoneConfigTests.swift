import Testing
@testable import Pommora

@Suite("ItemWindowZoneConfig")
struct ItemWindowZoneConfigTests {
    @Test func combinedTotalCapsAcrossPoolA() {
        let pinned: [PropertyType] = [.select, .select, .select, .multiSelect]
        #expect(ItemWindowZoneConfig.isAtCap(.select, pinnedTypes: pinned))
    }
    @Test func perTypePoolBCapsEachIndependently() {
        let pinned: [PropertyType] = [.checkbox]
        #expect(ItemWindowZoneConfig.isAtCap(.checkbox, pinnedTypes: pinned))
        #expect(!ItemWindowZoneConfig.isAtCap(.status, pinnedTypes: pinned))
    }
    @Test func notInV1WinsOverCapReached() {
        let pinned: [PropertyType] = [.select, .select, .select, .multiSelect]
        #expect(ItemWindowZoneConfig.muteReason(.number, pinnedTypes: pinned) == .notInV1)
    }
    @Test func selectAndMultiAreV1Checkable() {
        #expect(ItemWindowZoneConfig.muteReason(.select, pinnedTypes: []) == nil)
        #expect(ItemWindowZoneConfig.muteReason(.checkbox, pinnedTypes: []) == .notInV1)
    }
    @Test func pinnedTypesResolvesViaSchemaAndFiltersToV1() {
        let schema = [PropertyDefinition(id: "s", name: "S", type: .select),
                      PropertyDefinition(id: "n", name: "N", type: .number)]
        let promoted = [PromotedProperty(id: "s"), PromotedProperty(id: "n")]
        #expect(ItemWindowZoneConfig.pinnedTypes(promoted: promoted, schema: schema) == [.select])
    }
    @Test func combinedTotalUnderCapAndPoolC() {
        #expect(!ItemWindowZoneConfig.isAtCap(.select, pinnedTypes: [.select, .multiSelect]))   // 2 of 4 — under
        #expect(!ItemWindowZoneConfig.isAtCap(.url, pinnedTypes: [.url]))                       // 1 of 2 — under
        #expect(ItemWindowZoneConfig.isAtCap(.url, pinnedTypes: [.url, .file]))                 // 2 of 2 — at cap (Pool C)
    }
}
