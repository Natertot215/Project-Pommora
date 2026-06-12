import Foundation
import Testing

@testable import Pommora

/// Covers `PropertyColumnBuilder.columns(view:schema:)` tier-column emission:
/// the three tier relation columns (tier3 / tier2 / tier1) are emitted
/// rightmost-before-Modified, are individually hideable, and only appear when
/// their def is present in the schema.
@Suite("PropertyColumnBuilder") struct PropertyColumnBuilderTests {

    // MARK: - Fixtures

    /// A plain user property (non-relation, non-reserved).
    private func userProp(id: String = "prop_user", name: String = "Notes") -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .url)
    }

    /// A tier relation def keyed by a reserved tier ID, targeting its context tier.
    private func tierDef(id: String, name: String, tier: Int) -> PropertyDefinition {
        PropertyDefinition(
            id: id,
            name: name,
            type: .relation,
            relationTarget: .contextTier(tier)
        )
    }

    private var tier1Def: PropertyDefinition { tierDef(id: ReservedPropertyID.tier1, name: "Area", tier: 1) }
    private var tier2Def: PropertyDefinition { tierDef(id: ReservedPropertyID.tier2, name: "Topic", tier: 2) }
    private var tier3Def: PropertyDefinition { tierDef(id: ReservedPropertyID.tier3, name: "Project", tier: 3) }

    private func view(hidden: [String] = []) -> SavedView {
        SavedView(id: "view_test", propertyOrder: ["_title"], hiddenProperties: hidden)
    }

    // MARK: - Tier emission order

    @Test func emitsTierColumnsRightmostBeforeModifiedInOrder() {
        let schema = [userProp(), tier1Def, tier2Def, tier3Def]
        let columns = PropertyColumnBuilder.columns(view: view(), schema: schema)

        // Leads with title; the user prop appears as a column.
        #expect(columns.first?.id == "_title")
        #expect(columns.contains { $0.id == "prop_user" })

        // The last four columns are the three tiers (tier3, tier2, tier1) then Modified.
        let tail = columns.suffix(4).map(\.id)
        #expect(
            tail == [
                ReservedPropertyID.tier3,
                ReservedPropertyID.tier2,
                ReservedPropertyID.tier1,
                "_modified_at",
            ]
        )

        // Modified is the absolute trailer.
        #expect(columns.last?.id == "_modified_at")
    }

    // MARK: - Hideability

    @Test func hiddenTierIsOmitted() {
        let schema = [userProp(), tier1Def, tier2Def, tier3Def]
        let columns = PropertyColumnBuilder.columns(
            view: view(hidden: [ReservedPropertyID.tier2]),
            schema: schema
        )

        #expect(!columns.contains { $0.id == ReservedPropertyID.tier2 })

        // Remaining tiers keep their order; Modified still trails.
        let tail = columns.suffix(3).map(\.id)
        #expect(tail == [ReservedPropertyID.tier3, ReservedPropertyID.tier1, "_modified_at"])
    }

    // MARK: - Guard: no tier defs in schema

    @Test func schemaWithoutTiersEmitsNoTierColumns() {
        let schema = [userProp()]
        let columns = PropertyColumnBuilder.columns(view: view(), schema: schema)

        // title + user prop + Modified only — no tier columns appear.
        #expect(columns.map(\.id) == ["_title", "prop_user", "_modified_at"])
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier3 })
    }
}
