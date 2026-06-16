//
//  GroupResolverTests.swift
//  PommoraTests
//
//  Pure-logic tests for the view-pipeline group engine. No disk.
//

import Foundation
import Testing

@testable import Pommora

struct GroupResolverTests {
    private let collA = VPFixture.collection("coll_A", title: "Alpha")
    private let collB = VPFixture.collection("coll_B", title: "Beta")

    // MARK: - Structural: VAULT scope (Collection → Set children)

    @Test func structuralVaultGroupsByCollectionWithNestedSets() {
        let setX = VPFixture.set("set_X", title: "X", collection: "coll_A")
        let items = [
            VPFixture.item("p1", title: "Loose", in: collA),  // loose in collA
            VPFixture.item("p2", title: "InSet", in: setX, of: collA),  // in set X
            VPFixture.item("p3", title: "BetaPage", in: collB),  // loose in collB
        ]
        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .vault)

        #expect(groups.count == 2)
        let alpha = groups[0]
        #expect(alpha.id == "coll_A")
        #expect(alpha.title == "Alpha")
        #expect(alpha.items.map(\.id) == ["p1"])  // loose page in collection's own items
        #expect(alpha.children?.count == 1)
        #expect(alpha.children?[0].id == "set_X")
        #expect(alpha.children?[0].items.map(\.id) == ["p2"])  // nested set's page

        let beta = groups[1]
        #expect(beta.id == "coll_B")
        #expect(beta.children == nil)
        #expect(beta.items.map(\.id) == ["p3"])
    }

    @Test func structuralVaultRootPagesGoInTrailingUngroupedBand() {
        let items = [
            VPFixture.item("p1", title: "InColl", in: collA),
            VPFixture.rootItem("p2", title: "Root"),
        ]
        let groups = GroupResolver.resolve(items: items, config: nil, scope: .vault)
        #expect(groups.count == 2)
        #expect(groups[0].id == "coll_A")
        #expect(groups[1].id == GroupResolver.ungroupedID)
        #expect(groups[1].kind == .ungrouped)
        #expect(groups[1].items.map(\.id) == ["p2"])
    }

    // MARK: - flattenedItems (no page lost)

    @Test func flattenedItemsIncludesAllDescendants() {
        let setX = VPFixture.set("set_X", title: "X", collection: "coll_A")
        let setY = VPFixture.set("set_Y", title: "Y", collection: "coll_A")
        let items = [
            VPFixture.item("loose", title: "Loose", in: collA),
            VPFixture.item("inX", title: "InX", in: setX, of: collA),
            VPFixture.item("inY", title: "InY", in: setY, of: collA),
        ]
        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .vault)
        #expect(groups.count == 1)
        let flat = groups[0].flattenedItems.map(\.id).sorted()
        #expect(flat == ["inX", "inY", "loose"])  // own items + every set's items
    }

    // MARK: - Structural: COLLECTION scope (Sets + ungrouped band)

    @Test func structuralCollectionScopeSetsPlusUngroupedBand() {
        let setX = VPFixture.set("set_X", title: "X", collection: "coll_A")
        let items = [
            VPFixture.item("p1", title: "InSet", in: setX, of: collA),
            VPFixture.item("p2", title: "Loose", in: collA),  // no set → root band
        ]
        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .collection)
        #expect(groups.count == 2)
        #expect(groups[0].id == "set_X")
        #expect(groups[0].kind == .structuralSet(setX))
        #expect(groups[1].id == GroupResolver.ungroupedID)
        #expect(groups[1].items.map(\.id) == ["p2"])
    }

    @Test func structuralCollectionZeroSetsIsHeaderlessSingleBand() {
        let items = [
            VPFixture.item("p1", title: "A", in: collA),
            VPFixture.item("p2", title: "B", in: collA),
        ]
        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .collection)
        #expect(groups.count == 1)
        #expect(groups[0].id == GroupResolver.ungroupedID)
        #expect(groups[0].title == "")  // headerless (no Set headers, flat look)
        #expect(groups[0].kind == .ungrouped)
        #expect(groups[0].items.count == 2)
    }

    // MARK: - Property buckets

    @Test func propertyBucketsInSchemaOptionOrderPlusNoValue() {
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("medium", "Medium"), ("low", "Low")])
        let items = [
            VPFixture.item("a", title: "A", in: collA, properties: ["prop_p": .select("low")]),
            VPFixture.item("b", title: "B", in: collA, properties: ["prop_p": .select("high")]),
            VPFixture.item("c", title: "C", in: collA),  // no value → trailing bucket
        ]
        let groups = GroupResolver.resolve(
            items: items, config: .property(PropertyGrouping(propertyID: "prop_p", order: nil)),
            scope: .collection, schema: [def])
        // Option order: high (has b), medium (empty → skipped), low (has a), then No-value.
        #expect(groups.map(\.id) == ["high", "low", GroupResolver.ungroupedID])
        #expect(groups[0].title == "High")
        #expect(groups[2].title == "No Priority")
        #expect(groups[2].kind == .propertyBucket(value: nil))
    }

    @Test func propertyBucketsHonorOrderOverride() {
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("medium", "Medium"), ("low", "Low")])
        let items = [
            VPFixture.item("a", title: "A", in: collA, properties: ["prop_p": .select("low")]),
            VPFixture.item("b", title: "B", in: collA, properties: ["prop_p": .select("high")]),
        ]
        // Override reverses to low-first.
        let groups = GroupResolver.resolve(
            items: items,
            config: .property(PropertyGrouping(propertyID: "prop_p", orderMode: .manual, order: ["low", "medium", "high"])),
            scope: .collection, schema: [def])
        #expect(groups.map(\.id) == ["low", "high"])  // medium skipped (empty)
    }

    // MARK: - Flat

    @Test func flatIsSingleGroupAllItems() {
        let setX = VPFixture.set("set_X", title: "X", collection: "coll_A")
        let items = [
            VPFixture.item("p1", title: "A", in: collA),
            VPFixture.item("p2", title: "B", in: setX, of: collA),
        ]
        let groups = GroupResolver.resolve(items: items, config: .flat, scope: .vault)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .ungrouped)
        #expect(groups[0].items.count == 2)
    }

    // MARK: - Collapse behavior

    @Test func collapsedGroupStillAppearsWithFlag() {
        let items = [VPFixture.item("p1", title: "A", in: collA)]
        let groups = GroupResolver.resolve(
            items: items, config: .structural, scope: .vault,
            collapsed: ["coll_A"])
        #expect(groups.count == 1)
        #expect(groups[0].isCollapsed)  // header shows; renderer hides items
        #expect(groups[0].items.map(\.id) == ["p1"])  // items still carried
    }

    // MARK: - Composition: group THEN sort within

    @Test func sortingAppliesWithinEachGroup() {
        let setX = VPFixture.set("set_X", title: "X", collection: "coll_A")
        let items = [
            VPFixture.item("p3", title: "Zebra", in: collA),
            VPFixture.item("p1", title: "Apple", in: collA),
            VPFixture.item("p2", title: "Mango", in: setX, of: collA),
            VPFixture.item("p4", title: "Banana", in: setX, of: collA),
        ]
        let groups = GroupResolver.resolve(
            items: items, config: .structural, scope: .vault,
            sort: SortCriterion(propertyID: "_title", direction: .ascending))
        // Collection's own items sorted by title: Apple(p1), Zebra(p3).
        #expect(groups[0].items.map(\.id) == ["p1", "p3"])
        // Nested set's items sorted by title: Banana(p4), Mango(p2).
        #expect(groups[0].children?[0].items.map(\.id) == ["p4", "p2"])
    }

    @Test func manualSortPreservesInputOrderWithinGroup() {
        let items = [
            VPFixture.item("p3", title: "Zebra", in: collA),
            VPFixture.item("p1", title: "Apple", in: collA),
        ]
        let groups = GroupResolver.resolve(
            items: items, config: .structural, scope: .collection, sort: nil)
        #expect(groups[0].items.map(\.id) == ["p3", "p1"])  // input order kept
    }
}
