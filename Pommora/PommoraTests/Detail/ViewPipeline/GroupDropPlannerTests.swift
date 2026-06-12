import Foundation
import Testing

@testable import Pommora

@Suite("GroupDropPlanner")
struct GroupDropPlannerTests {

    // MARK: - Fixtures

    private func vault(_ id: String = "type1") -> PageType {
        PageType(
            id: id, title: "Notes", icon: nil,
            properties: [], views: [], modifiedAt: Date())
    }

    private func collection(_ id: String, in vault: PageType) -> PageCollection {
        PageCollection(
            id: id, typeID: vault.id, title: id,
            folderURL: URL(fileURLWithPath: "/tmp/\(id)"), modifiedAt: Date())
    }

    private func set(_ id: String, in collection: PageCollection) -> PageSet {
        PageSet(
            id: id, collectionID: collection.id, title: id,
            folderURL: URL(fileURLWithPath: "/tmp/\(id)"), modifiedAt: Date())
    }

    // MARK: - Non-page / group-row source → .none

    @Test("A non-page (group-row) source is never a drag source → .none")
    func nonPageSourceIsNone() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"],
            isPageRows: false,  // group row / non-page
            group: .structural(parent),
            parent: parent)
        let target = GroupDropPlanner.Target(
            group: .structural(parent), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: nil, sourceIndices: IndexSet([0]))

        #expect(plan == .none)
    }

    @Test("An empty page-id set → .none")
    func emptyPageIDsIsNone() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: [], isPageRows: true,
            group: .structural(parent), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .structural(parent), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: nil, sourceIndices: IndexSet())

        #expect(plan == .none)
    }

    // MARK: - Reorder: same container, manual sort

    @Test("Same structural container + manual sort → .reorder")
    func reorderSameContainerManual() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .structural(parent), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .structural(parent), insertionIndex: 2)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: nil, sourceIndices: IndexSet([0]))

        #expect(plan == .reorder(IndexSet([0]), 2))
    }

    @Test("Same container but sort != nil → reorder blocked → .none")
    func reorderBlockedWhenSorted() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .structural(parent), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .structural(parent), insertionIndex: 2)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: false, groupPropertyID: nil, sourceIndices: IndexSet([0]))

        #expect(plan == .none)
    }

    @Test("Same property bucket + manual sort → .reorder")
    func reorderSamePropertyBucketManual() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .property(value: "todo"), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .property(value: "todo"), insertionIndex: 1)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: "status", sourceIndices: IndexSet([3]))

        #expect(plan == .reorder(IndexSet([3]), 1))
    }

    // MARK: - Move: different structural group

    @Test("Drop into a different structural group → .move")
    func moveToOtherStructuralGroup() {
        let v = vault()
        let coll = collection("c1", in: v)
        let other = collection("c2", in: v)
        let sourceParent = PageParent.collection(coll, vault: v)
        let destParent = PageParent.collection(other, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .structural(sourceParent), parent: sourceParent)
        let target = GroupDropPlanner.Target(
            group: .structural(destParent), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: nil, sourceIndices: IndexSet([0]))

        #expect(plan == .move(to: destParent))
    }

    @Test("Move into a Set from the collection root")
    func moveIntoSet() {
        let v = vault()
        let coll = collection("c1", in: v)
        let s = set("s1", in: coll)
        let sourceParent = PageParent.collection(coll, vault: v)
        let destParent = PageParent.set(s, collection: coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .structural(sourceParent), parent: sourceParent)
        let target = GroupDropPlanner.Target(
            group: .structural(destParent), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: false, groupPropertyID: nil, sourceIndices: IndexSet())

        #expect(plan == .move(to: destParent))
    }

    // MARK: - Rewrite property: different bucket

    @Test("Drop into a different property bucket → .rewriteProperty(value)")
    func rewriteToPropertyBucket() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .property(value: "todo"), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .property(value: "done"), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: "status", sourceIndices: IndexSet([0]))

        #expect(plan == .rewriteProperty(id: "status", value: "done"))
    }

    @Test("Drop into the ungrouped bucket → .rewriteProperty(value: nil)")
    func rewriteToUngroupedBucketIsNil() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .property(value: "todo"), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .property(value: nil), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: "status", sourceIndices: IndexSet([0]))

        #expect(plan == .rewriteProperty(id: "status", value: nil))
    }

    @Test("Property-bucket drop with no known group property → .none")
    func propertyBucketWithoutGroupPropertyIsNone() {
        let v = vault()
        let coll = collection("c1", in: v)
        let parent = PageParent.collection(coll, vault: v)
        let source = GroupDropPlanner.Source(
            pageIDs: ["p1"], isPageRows: true,
            group: .property(value: "todo"), parent: parent)
        let target = GroupDropPlanner.Target(
            group: .property(value: "done"), insertionIndex: 0)

        let plan = GroupDropPlanner.plan(
            source: source, target: target,
            sortIsManual: true, groupPropertyID: nil, sourceIndices: IndexSet([0]))

        #expect(plan == .none)
    }
}
