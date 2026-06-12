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

/// Container-space correctness for the reorder commit (HIGH #2). The view's drag
/// path computes indices in the FILTERED / BUCKETED group subset; the commit
/// hands off moving ids + an anchor id, and `PageContentManager.reorderedIDs`
/// translates that into the canonical STORED-array order. These exercise the
/// case the index-based path corrupted: a reorder inside a property bucket whose
/// subset ≠ the full container.
@Suite("ReorderByID")
struct ReorderByIDTests {

    /// Full container [a, b, c, d, e]; the "todo" bucket the user sees is only
    /// [a, c, e]. Dragging `e` before `c` (a within-bucket move) must reorder the
    /// FULL container to [a, e, b, c, d] — `e` lands before `c`, untouched
    /// non-bucket rows (`b`, `d`) keep their absolute positions. The old
    /// index-based path would have moved a different element.
    @Test("Within-bucket reorder maps to stored-array order, not the subset")
    func withinBucketReorderUsesStoredOrder() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c", "d", "e"], movingIDs: ["e"], before: "c")
        #expect(result == ["a", "b", "e", "c", "d"])
    }

    @Test("Nil anchor appends moving ids at the container end")
    func nilAnchorAppends() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c"], movingIDs: ["a"], before: nil)
        #expect(result == ["b", "c", "a"])
    }

    @Test("Multi-drag preserves the moving ids' given order at the anchor")
    func multiDragKeepsOrder() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c", "d"], movingIDs: ["d", "b"], before: "a")
        #expect(result == ["d", "b", "a", "c"])
    }

    @Test("An absent anchor falls through to append")
    func absentAnchorAppends() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c"], movingIDs: ["b"], before: "zzz")
        #expect(result == ["a", "c", "b"])
    }
}
