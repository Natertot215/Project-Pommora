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
            VPFixture.item("p1", title: "Loose", in: collA),
            VPFixture.item("p2", title: "InSet", in: setX, of: collA),
            VPFixture.item("p3", title: "BetaPage", in: collB),
        ]
        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .pageCollection)

        #expect(groups.count == 2)
        let alpha = groups[0]
        #expect(alpha.id == "coll_A")
        #expect(alpha.title == "Alpha")
        #expect(alpha.items.map(\.id) == ["p1"])
        #expect(alpha.children?.count == 1)
        #expect(alpha.children?[0].id == "set_X")
        #expect(alpha.children?[0].items.map(\.id) == ["p2"])

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
        let groups = GroupResolver.resolve(items: items, config: nil, scope: .pageCollection)
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
        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .pageCollection)
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
        let groups = GroupResolver.resolve(items: items, config: .flat, scope: .pageCollection)
        #expect(groups.count == 1)
        #expect(groups[0].kind == .ungrouped)
        #expect(groups[0].items.count == 2)
    }

    // MARK: - Collapse behavior

    @Test func collapsedGroupStillAppearsWithFlag() {
        let items = [VPFixture.item("p1", title: "A", in: collA)]
        let groups = GroupResolver.resolve(
            items: items, config: .structural, scope: .pageCollection,
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
            items: items, config: .structural, scope: .pageCollection,
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

    // MARK: - N-deep structural grouping

    @Test("4-deep tree: SetA→SubB→SubC each get their own group level with correct items")
    func fourDeepStructuralGrouping() {
        // Type → Collection (collA) → SetA → SubB → SubC, pages at each level.
        let setA = VPFixture.set("set_A", title: "SetA", collection: "coll_A")
        let subB = PageSet(
            id: "sub_B", parentID: "set_A", title: "SubB",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))
        let subC = PageSet(
            id: "sub_C", parentID: "sub_B", title: "SubC",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))

        let items = [
            VPFixture.item("loose", title: "Loose", in: collA),        // collection root
            VPFixture.item("pA", title: "InSetA", in: setA, of: collA), // SetA direct
            VPFixture.item("pB", title: "InSubB", inSubSet: subB, of: collA), // SubB
            VPFixture.item("pC", title: "InSubC", inSubSet: subC, of: collA), // SubC
        ]

        let groups = GroupResolver.resolve(items: items, config: .structural, scope: .collection)

        // Top level: SetA group + trailing ungrouped band.
        #expect(groups.count == 2)
        let setAGroup = groups[0]
        #expect(setAGroup.id == "set_A")
        #expect(setAGroup.items.map(\.id) == ["pA"])

        // SetA → SubB child.
        let subBGroup = setAGroup.children?.first
        #expect(subBGroup?.id == "sub_B")
        #expect(subBGroup?.items.map(\.id) == ["pB"])

        // SubB → SubC child.
        let subCGroup = subBGroup?.children?.first
        #expect(subCGroup?.id == "sub_C")
        #expect(subCGroup?.items.map(\.id) == ["pC"])

        // SubC has no further children.
        #expect(subCGroup?.children == nil)

        // Trailing ungrouped band carries the collection-root loose page.
        let ungrouped = groups[1]
        #expect(ungrouped.id == GroupResolver.ungroupedID)
        #expect(ungrouped.items.map(\.id) == ["loose"])
    }

    @Test("collapse at depth-3 collapses only that node, siblings and ancestors unaffected")
    func collapseAtDepthThreeIsIsolated() {
        let setA = VPFixture.set("set_A", title: "SetA", collection: "coll_A")
        let subB = PageSet(
            id: "sub_B", parentID: "set_A", title: "SubB",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))
        let subC = PageSet(
            id: "sub_C", parentID: "sub_B", title: "SubC",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))
        let subD = PageSet(
            id: "sub_D", parentID: "sub_B", title: "SubD",
            folderURL: URL(fileURLWithPath: "/"), modifiedAt: Date(timeIntervalSince1970: 0))

        let items = [
            VPFixture.item("pA", title: "InSetA", in: setA, of: collA),
            VPFixture.item("pB", title: "InSubB", inSubSet: subB, of: collA),
            VPFixture.item("pC", title: "InSubC", inSubSet: subC, of: collA),
            VPFixture.item("pD", title: "InSubD", inSubSet: subD, of: collA),
        ]

        // Collapse only subC's id.
        let groups = GroupResolver.resolve(
            items: items, config: .structural, scope: .collection, collapsed: ["sub_C"])

        let setAGroup = groups[0]
        #expect(!setAGroup.isCollapsed)

        let subBGroup = setAGroup.children?.first
        #expect(subBGroup?.isCollapsed == false)

        // Find subC and subD among subB's children.
        let subCGroup = subBGroup?.children?.first(where: { $0.id == "sub_C" })
        let subDGroup = subBGroup?.children?.first(where: { $0.id == "sub_D" })

        #expect(subCGroup?.isCollapsed == true)   // only subC collapsed
        #expect(subDGroup?.isCollapsed == false)  // sibling unaffected
    }
}
