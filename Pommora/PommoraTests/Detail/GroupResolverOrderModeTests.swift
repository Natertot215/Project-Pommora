import Foundation
import Testing
@testable import Pommora

@Suite("GroupResolverOrderModeTests") struct GroupResolverOrderModeTests {
    private let coll = VPFixture.collection("coll_1", title: "Items")

    // MARK: - (a) .reversed flips .configured order (Select)

    @Test("reversed mode returns configured order flipped for Select")
    func reversedSelectOrder() {
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("medium", "Medium"), ("low", "Low")])
        let items = [
            VPFixture.item("a", title: "A", in: coll, properties: ["prop_p": .select("high")]),
            VPFixture.item("b", title: "B", in: coll, properties: ["prop_p": .select("low")]),
            VPFixture.item("c", title: "C", in: coll, properties: ["prop_p": .select("medium")]),
        ]
        let grouping = PropertyGrouping(propertyID: "prop_p", orderMode: .reversed)
        let groups = GroupResolver.resolve(
            items: items, config: .property(grouping), scope: .collection, schema: [def])
        // configured order: high, medium, low — reversed: low, medium, high
        #expect(groups.map(\.id) == ["low", "medium", "high"])
    }

    // MARK: - (b) .configured Status groups in schema option order

    @Test("configured mode Status groups appear in schema option order")
    func configuredStatusOrder() {
        let statusGroups = PropertyDefinition.StatusGroup.defaultSeed()
        let def = PropertyDefinition(id: "prop_s", name: "Status", type: .status, statusGroups: statusGroups)
        // Default seed: not_started (upcoming) → in_progress (inProgress) → done (done)
        let items = [
            VPFixture.item("a", title: "A", in: coll, properties: ["prop_s": .status("done")]),
            VPFixture.item("b", title: "B", in: coll, properties: ["prop_s": .status("not_started")]),
            VPFixture.item("c", title: "C", in: coll, properties: ["prop_s": .status("in_progress")]),
        ]
        let grouping = PropertyGrouping(propertyID: "prop_s", orderMode: .configured)
        let groups = GroupResolver.resolve(
            items: items, config: .property(grouping), scope: .collection, schema: [def])
        #expect(groups.map(\.id) == ["not_started", "in_progress", "done"])
    }

    // MARK: - (c) emptyPlacement .top / .bottom

    @Test("emptyPlacement .top puts no-value bucket first")
    func emptyPlacementTop() {
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("low", "Low")])
        let items = [
            VPFixture.item("a", title: "A", in: coll, properties: ["prop_p": .select("high")]),
            VPFixture.item("b", title: "B", in: coll),  // no value
        ]
        let grouping = PropertyGrouping(propertyID: "prop_p", orderMode: .configured, emptyPlacement: .top)
        let groups = GroupResolver.resolve(
            items: items, config: .property(grouping), scope: .collection, schema: [def])
        #expect(groups.first?.id == GroupResolver.ungroupedID)
        #expect(groups.last?.id == "high")
    }

    @Test("emptyPlacement .bottom (default) puts no-value bucket last")
    func emptyPlacementBottom() {
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("low", "Low")])
        let items = [
            VPFixture.item("a", title: "A", in: coll, properties: ["prop_p": .select("high")]),
            VPFixture.item("b", title: "B", in: coll),  // no value
        ]
        let grouping = PropertyGrouping(propertyID: "prop_p", orderMode: .configured, emptyPlacement: .bottom)
        let groups = GroupResolver.resolve(
            items: items, config: .property(grouping), scope: .collection, schema: [def])
        #expect(groups.first?.id == "high")
        #expect(groups.last?.id == GroupResolver.ungroupedID)
    }

    // MARK: - (d) hideEmptyGroups removes no-value bucket

    @Test("hideEmptyGroups removes the no-value bucket entirely")
    func hideEmptyGroupsDropsNoValueBucket() {
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("low", "Low")])
        let items = [
            VPFixture.item("a", title: "A", in: coll, properties: ["prop_p": .select("high")]),
            VPFixture.item("b", title: "B", in: coll),  // no value — should be hidden
        ]
        let grouping = PropertyGrouping(propertyID: "prop_p", orderMode: .configured, hideEmptyGroups: true)
        let groups = GroupResolver.resolve(
            items: items, config: .property(grouping), scope: .collection, schema: [def])
        #expect(!groups.contains(where: { $0.id == GroupResolver.ungroupedID }))
        #expect(groups.count == 1)
        #expect(groups[0].id == "high")
    }

    // MARK: - (e) Checkbox: nil → "false"; no no-value bucket; configured = false-then-true

    @Test("unset checkbox item lands in Unchecked group; no no-value bucket; configured order is false-then-true")
    func checkboxNilToUnchecked() {
        let def = VPFixture.checkboxDef("prop_c", name: "Done")
        let items = [
            VPFixture.item("a", title: "A", in: coll, properties: ["prop_c": .checkbox(true)]),
            VPFixture.item("b", title: "B", in: coll),  // no value → must land in "false" (Unchecked)
        ]
        let grouping = PropertyGrouping(propertyID: "prop_c", orderMode: .configured)
        let groups = GroupResolver.resolve(
            items: items, config: .property(grouping), scope: .collection, schema: [def])
        // No ungrouped/no-value bucket
        #expect(!groups.contains(where: { $0.id == GroupResolver.ungroupedID }))
        // Configured order: false (Unchecked) first, true (Checked) second
        #expect(groups.map(\.id) == ["false", "true"])
        // Item b (no value) is in the "false" (Unchecked) group
        let unchecked = groups.first(where: { $0.id == "false" })
        #expect(unchecked?.items.contains(where: { $0.id == "b" }) == true)
    }

    // MARK: - (f) Missing property ID falls back to structural

    @Test("property config with unknown propertyID falls back to structural")
    func missingPropertyFallsBackToStructural() {
        let items = [
            VPFixture.item("a", title: "A", in: coll),
            VPFixture.item("b", title: "B", in: coll),
        ]
        let groupingMissing = PropertyGrouping(propertyID: "nonexistent_id")
        let structural = GroupResolver.resolve(
            items: items, config: .structural, scope: .collection, schema: [])
        let fallback = GroupResolver.resolve(
            items: items, config: .property(groupingMissing), scope: .collection, schema: [])
        #expect(fallback.map(\.id) == structural.map(\.id))
        // kind comparison skipped — ResolvedGroup.Kind does not conform to Equatable
    }
}
