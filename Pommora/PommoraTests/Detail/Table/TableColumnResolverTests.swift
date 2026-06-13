import Foundation
import Testing

@testable import Pommora

/// Covers `TableColumnResolver.resolve(view:schema:)` — the width- and
/// icon-bearing column resolver for the custom table. Resolver contract:
///   - `propertyOrder` consumed VERBATIM; Title may sit anywhere.
///   - `hiddenProperties` excludes columns (`_title` is never hidden).
///   - Tiers + `_modified_at` are DEFAULT-ON (Pass 3 appends them unless hidden
///     or already placed by `propertyOrder` — parity with the native table).
///   - Unaccounted schema properties append visible at the end.
///   - Cover never yields a column.
///
/// Tests that isolate a behavior other than the default-on injection pass
/// `hidden: [ReservedPropertyID.modifiedAt]` explicitly so the fixture
/// emits only what the test is checking. The "Pass 3" section covers the
/// default-on contract directly.
@Suite("TableColumnResolver") struct TableColumnResolverTests {

    // MARK: - Fixtures

    private func userProp(id: String = "prop_user", name: String = "Notes") -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .url)
    }

    private func tierDef(id: String, name: String, tier: Int) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .relation, relationTarget: .contextTier(tier))
    }

    private var tier1Def: PropertyDefinition { tierDef(id: ReservedPropertyID.tier1, name: "Area", tier: 1) }
    private var tier2Def: PropertyDefinition { tierDef(id: ReservedPropertyID.tier2, name: "Topic", tier: 2) }
    private var tier3Def: PropertyDefinition { tierDef(id: ReservedPropertyID.tier3, name: "Project", tier: 3) }

    private func view(
        order: [String] = [ReservedPropertyID.title],
        hidden: [String] = [],
        widths: [String: Double]? = nil
    ) -> SavedView {
        SavedView(
            id: "view_test",
            propertyOrder: order,
            hiddenProperties: hidden,
            columnWidths: widths
        )
    }

    // MARK: - propertyOrder consumed verbatim

    @Test func consumesPropertyOrderVerbatim() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: ["prop_user", ReservedPropertyID.title],
                hidden: [ReservedPropertyID.modifiedAt]
            ),
            schema: schema
        )
        #expect(columns.map(\.id) == ["prop_user", "_title"])
    }

    @Test func titleNeedNotBeFirst() {
        let schema = [userProp(id: "a", name: "A"), userProp(id: "b", name: "B")]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: ["a", ReservedPropertyID.title, "b"],
                hidden: [ReservedPropertyID.modifiedAt]
            ),
            schema: schema
        )
        #expect(columns.map(\.id) == ["a", "_title", "b"])
    }

    // MARK: - Hidden respected

    @Test func hiddenPropertyYieldsNoColumn() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title, "prop_user"], hidden: ["prop_user"]),
            schema: schema
        )
        #expect(!columns.contains { $0.id == "prop_user" })
    }

    @Test func tiersAndModifiedAreHideable() {
        let schema = [tier1Def, tier2Def, tier3Def]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: [
                    ReservedPropertyID.title, ReservedPropertyID.tier1, ReservedPropertyID.tier2,
                    ReservedPropertyID.tier3, ReservedPropertyID.modifiedAt,
                ],
                hidden: [ReservedPropertyID.tier2, ReservedPropertyID.modifiedAt]
            ),
            schema: schema
        )
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(!columns.contains { $0.id == ReservedPropertyID.modifiedAt })
        #expect(columns.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(columns.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test func titleIsNeverHidden() {
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title], hidden: [ReservedPropertyID.title]),
            schema: []
        )
        #expect(columns.contains { $0.id == ReservedPropertyID.title })
    }

    @Test func titleInjectedAtFrontWhenAbsentFromOrder() {
        let schema = [userProp(id: "a", name: "A")]
        let columns = TableColumnResolver.resolve(
            view: view(order: ["a"], hidden: [ReservedPropertyID.modifiedAt]),
            schema: schema
        )
        // Title is structurally guaranteed at the FRONT even though
        // `property_order` omits it entirely.
        #expect(columns.first?.id == ReservedPropertyID.title)
        #expect(columns.first?.kind == .title)
        #expect(columns.map(\.id) == [ReservedPropertyID.title, "a"])
    }

    @Test func titleIsOnlyColumnWhenOrderOmitsTitleAndSchemaEmpty() {
        let columns = TableColumnResolver.resolve(
            view: view(order: [], hidden: [ReservedPropertyID.modifiedAt]),
            schema: []
        )
        #expect(columns.map(\.id) == [ReservedPropertyID.title])
        #expect(columns.first?.kind == .title)
    }

    // MARK: - Unaccounted append

    @Test func unaccountedPropertiesAppendVisibleAtEnd() {
        let schema = [userProp(id: "known"), userProp(id: "fresh", name: "Fresh")]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: [ReservedPropertyID.title, "known"],
                hidden: [ReservedPropertyID.modifiedAt]
            ),
            schema: schema
        )
        #expect(columns.map(\.id) == ["_title", "known", "fresh"])
    }

    @Test func hiddenUnaccountedPropertyDoesNotAppend() {
        let schema = [userProp(id: "fresh")]
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title], hidden: ["fresh"]),
            schema: schema
        )
        #expect(!columns.contains { $0.id == "fresh" })
    }

    // MARK: - Cover never a column

    @Test func coverNeverYieldsColumn() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: [ReservedPropertyID.title, "cover", "prop_user"],
                hidden: [ReservedPropertyID.modifiedAt]
            ),
            schema: schema
        )
        #expect(!columns.contains { $0.id == "cover" })
        #expect(columns.map(\.id) == ["_title", "prop_user"])
    }

    // MARK: - Stale order reference skipped

    @Test func orderReferenceMissingFromSchemaIsSkipped() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title, "deleted_prop", "prop_user"]),
            schema: schema
        )
        #expect(!columns.contains { $0.id == "deleted_prop" })
    }

    // MARK: - Width fallback + clamp

    @Test func widthFallsBackToKindDefault() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title, "prop_user"]),
            schema: schema
        )
        let titleCol = columns.first { $0.id == ReservedPropertyID.title }
        let propCol = columns.first { $0.id == "prop_user" }
        #expect(titleCol?.width == TableColumnResolver.defaultWidth(for: .title))
        #expect(propCol?.width == TableColumnResolver.defaultWidth(for: .property))
    }

    @Test func explicitWidthHonored() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title, "prop_user"], widths: ["prop_user": 320]),
            schema: schema
        )
        #expect(columns.first { $0.id == "prop_user" }?.width == 320)
    }

    @Test func widthClampedToSixtyMinimum() {
        let schema = [userProp()]
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title, "prop_user"], widths: ["prop_user": 10]),
            schema: schema
        )
        #expect(columns.first { $0.id == "prop_user" }?.width == 60)
    }

    // MARK: - Icons

    @Test func eachColumnCarriesAnIcon() {
        let schema = [userProp(), tier1Def]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: [
                    ReservedPropertyID.title, "prop_user", ReservedPropertyID.tier1,
                    ReservedPropertyID.modifiedAt,
                ]
            ),
            schema: schema
        )
        for col in columns {
            #expect(!col.iconName.isEmpty)
        }
        #expect(columns.first { $0.id == ReservedPropertyID.title }?.iconName == "textformat")
        #expect(columns.first { $0.id == ReservedPropertyID.modifiedAt }?.iconName == "clock")
        // URL user-property icon = PropertyType.url.pickerIcon ("link").
        #expect(columns.first { $0.id == "prop_user" }?.iconName == "link")
    }

    // MARK: - Kinds

    @Test func reservedIDsResolveToTheirKinds() {
        let schema = [userProp(), tier1Def]
        let columns = TableColumnResolver.resolve(
            view: view(
                order: [
                    ReservedPropertyID.title, "prop_user", ReservedPropertyID.tier1,
                    ReservedPropertyID.modifiedAt,
                ]
            ),
            schema: schema
        )
        #expect(columns.first { $0.id == ReservedPropertyID.title }?.kind == .title)
        #expect(columns.first { $0.id == "prop_user" }?.kind == .property)
        #expect(columns.first { $0.id == ReservedPropertyID.tier1 }?.kind == .tier)
        #expect(columns.first { $0.id == ReservedPropertyID.modifiedAt }?.kind == .modified)
    }

    // MARK: - Pass 3: default-on reserved columns

    @Test func modifiedColumnIsDefaultOnWhenNotInOrder() {
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title]),
            schema: []
        )
        // Pass 3 appends `_modified_at` by default (native-table parity).
        #expect(columns.last?.id == ReservedPropertyID.modifiedAt)
        #expect(columns.last?.kind == .modified)
    }

    @Test func tierColumnIsDefaultOnWhenSchemaDefExists() {
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title], hidden: [ReservedPropertyID.modifiedAt]),
            schema: [tier1Def]
        )
        #expect(columns.contains { $0.id == ReservedPropertyID.tier1 })
    }

    @Test func tierColumnDoesNotInjectWithoutSchemaDef() {
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title], hidden: [ReservedPropertyID.modifiedAt]),
            schema: []
        )
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier1 })
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier2 })
        #expect(!columns.contains { $0.id == ReservedPropertyID.tier3 })
    }

    @Test func hiddenModifiedSuppressesDefaultOn() {
        let columns = TableColumnResolver.resolve(
            view: view(order: [ReservedPropertyID.title], hidden: [ReservedPropertyID.modifiedAt]),
            schema: []
        )
        #expect(!columns.contains { $0.id == ReservedPropertyID.modifiedAt })
    }
}
