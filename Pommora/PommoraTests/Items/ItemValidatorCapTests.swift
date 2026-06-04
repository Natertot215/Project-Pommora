import Foundation
import Testing

@testable import Pommora

/// Task 1.6: the per-Item description cap drops to 250 (LD-7) with a per-Type
/// override via `ItemTemplateConfig.descriptionCap`. The over-cap throw now
/// carries the resolved cap as a payload (`descriptionTooLong(cap:)`), and the
/// error → message mapper (`friendly`) relocated onto `ItemValidator`.
@Suite("ItemValidatorCap")
struct ItemValidatorCapTests {

    @Test("default cap is 250")
    func defaultCapIs250() {
        #expect(ItemValidator.maxDescriptionLength == 250)
    }

    @Test("effective cap uses the Type template override, else the 250 default")
    func effectiveCapUsesTypeOverride() {
        let withOverride = ItemType(
            id: "1", title: "T", icon: nil, properties: [], views: [],
            templateConfig: ItemTemplateConfig(descriptionCap: 500),
            modifiedAt: Date(timeIntervalSince1970: 0))
        #expect(ItemValidator.effectiveCap(for: withOverride) == 500)

        let plain = ItemType(
            id: "2", title: "T", icon: nil, properties: [], views: [],
            modifiedAt: Date(timeIntervalSince1970: 0))
        #expect(ItemValidator.effectiveCap(for: plain) == 250)
    }

    @Test("over the effective cap throws .descriptionTooLong(cap:)")
    func rejectsOverEffectiveCap() {
        let t = ItemType(
            id: "1", title: "T", icon: nil, properties: [], views: [],
            modifiedAt: Date(timeIntervalSince1970: 0))
        #expect(throws: ItemValidator.ValidationError.descriptionTooLong(cap: 250)) {
            try ItemValidator.validate(
                title: "x", tier1: [], tier2: [], tier3: [],
                description: String(repeating: "a", count: 251),
                properties: [:], itemType: t, context: .empty)
        }
    }
}
