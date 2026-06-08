import Testing
import Foundation
@testable import Pommora

/// A6 — `TemplateResolver.promotedForField` is the chip-eligible subset of
/// `promotedEntries` (pinned properties whose type is in
/// `ItemWindowZoneConfig.v1Checkable`). The Item Window's segmented property
/// bar + inspector consume this to keep only V1-checkable pinned properties.
/// It must NOT alter `promotedEntries` order — it only filters.
@Suite("PromotedForField")
struct PromotedForFieldTests {
    /// A chip-eligible (`.select`) promoted property is kept; a non-checkable
    /// (`.number`) one is dropped, in promoted order.
    @Test func promotedForFieldKeepsChipEligibleDropsRest() {
        let sel = PropertyDefinition(id: "s", name: "Stage", type: .select)
        let num = PropertyDefinition(id: "n", name: "Count", type: .number)
        let type = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [sel, num], views: [],
            templateConfig: ItemTemplateConfig(
                promotedProperties: [
                    PromotedProperty(id: "s", display: nil),
                    PromotedProperty(id: "n", display: nil),
                ]
            ),
            modifiedAt: Date()
        )
        let out = TemplateResolver.promotedForField(type: type, collection: nil)
        #expect(out.map(\.definition.id) == ["s"])  // select kept, number (not v1Checkable) dropped
    }
}
