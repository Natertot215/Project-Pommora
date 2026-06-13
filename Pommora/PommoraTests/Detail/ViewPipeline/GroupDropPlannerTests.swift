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
            sortIsManual: true, groupPropertyID: nil)

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
            sortIsManual: true, groupPropertyID: nil)

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
            sortIsManual: true, groupPropertyID: nil)

        #expect(plan == .reorder)
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
            sortIsManual: false, groupPropertyID: nil)

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
            sortIsManual: true, groupPropertyID: "status")

        #expect(plan == .reorder)
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
            sortIsManual: true, groupPropertyID: nil)

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
            sortIsManual: false, groupPropertyID: nil)

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
            sortIsManual: true, groupPropertyID: "status")

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
            sortIsManual: true, groupPropertyID: "status")

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
            sortIsManual: true, groupPropertyID: nil)

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

    /// Drop a single dragged row onto its OWN top-half: anchor == the moving id.
    /// The effective anchor resolves to the first non-moving id at/after `c`'s
    /// index (`d`), so `c` lands before `d` — i.e. a no-op equal to `current`.
    /// Previously `c` teleported to the end (`[a, b, d, e, c]`) and persisted.
    @Test("Anchor in movingIDs (single drop-on-self) is an in-place no-op")
    func anchorInMovingSingleIsNoOp() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c", "d", "e"], movingIDs: ["c"], before: "c")
        #expect(result == ["a", "b", "c", "d", "e"])
    }

    /// Multi-drag dropped onto one of its own members: drag [b, d], anchor `b`.
    /// Effective anchor = first non-moving at/after index 1 = `c`, so the block
    /// inserts before `c` → [a, b, d, c, e].
    @Test("Anchor in movingIDs (multi-drag) resolves to next non-moving id")
    func anchorInMovingMultiResolves() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c", "d", "e"], movingIDs: ["b", "d"], before: "b")
        #expect(result == ["a", "b", "d", "c", "e"])
    }

    /// A stray moving id not in `current` is filtered; the real members still move.
    @Test("Stray movingID not in current is filtered, others still move")
    func strayMovingIDFiltered() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c"], movingIDs: ["zzz", "c"], before: "a")
        #expect(result == ["c", "a", "b"])
    }

    /// A duplicate id in movingIDs must not double-insert the moving block.
    @Test("Duplicate movingIDs do not double-insert")
    func duplicateMovingIDsDefensive() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c"], movingIDs: ["c", "c"], before: "a")
        #expect(result == ["c", "a", "b"])
    }

    /// Moving the entire container onto its own first member stays stable/sane.
    @Test("movingIDs == entire current stays stable")
    func movingEntireContainerStable() {
        let result = PageContentManager.reorderedIDs(
            current: ["a", "b", "c"], movingIDs: ["a", "b", "c"], before: "a")
        #expect(result == ["a", "b", "c"])
    }
}
