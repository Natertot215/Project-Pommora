import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Tests for `DetailReorderPlanner` — the pure helper that converts a
/// flat-table drag-drop into a kind-scoped reorder plan so dragging a page
/// never reorders collections, and vice versa.
///
/// Each test APPLIES the returned plan to the relevant kind-subset and
/// asserts the END-STATE order — not raw offset integers — so the tests are
/// robust to offset-convention details.
@Suite("DetailReorderPlannerTests")
struct DetailReorderPlannerTests {

    // MARK: - Fixtures

    /// Builds a leaf `DetailRow` carrying a minimal `PageMeta`.
    private func pageRow(id: String, title: String) -> DetailRow {
        let fm = PageFrontmatter(
            id: id, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let meta = PageMeta(
            id: id,
            title: title,
            url: URL(fileURLWithPath: "/tmp/\(id).md"),
            frontmatter: fm
        )
        return DetailRow(
            id: id,
            title: title,
            kind: .page(meta),
            iconName: "doc",
            modifiedAt: Date(timeIntervalSince1970: 0),
            children: nil
        )
    }

    /// Builds a leaf `DetailRow` carrying a minimal `PageCollection`.
    private func collectionRow(id: String, title: String) -> DetailRow {
        let coll = PageCollection(
            id: id,
            typeID: "type-1",
            title: title,
            folderURL: URL(fileURLWithPath: "/tmp/\(id)"),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
        return DetailRow(
            id: id,
            title: title,
            kind: .collection(coll),
            iconName: "folder",
            modifiedAt: Date(timeIntervalSince1970: 0),
            children: nil
        )
    }

    /// Builds a leaf `DetailRow` carrying a minimal `Item`.
    private func itemRow(id: String, title: String) -> DetailRow {
        let item = Item(
            id: id, title: title, icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
        return DetailRow(
            id: id,
            title: title,
            kind: .item(item),
            iconName: "doc",
            modifiedAt: Date(timeIntervalSince1970: 0),
            children: nil
        )
    }

    /// Builds a leaf `DetailRow` carrying a minimal `ItemCollection`.
    private func itemCollectionRow(id: String, title: String) -> DetailRow {
        let set = ItemCollection(
            id: id,
            typeID: "itype-1",
            title: title,
            folderURL: URL(fileURLWithPath: "/tmp/\(id)"),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
        return DetailRow(
            id: id,
            title: title,
            kind: .itemCollection(set),
            iconName: "folder",
            modifiedAt: Date(timeIntervalSince1970: 0),
            children: nil
        )
    }

    /// Applies `plan` to `subset` using `Array.move(fromOffsets:toOffset:)` and
    /// returns the reordered subset — mirrors how the detail view applies the plan.
    private func applyPlan(_ plan: DetailReorderPlan, to subset: [DetailRow]) -> [DetailRow] {
        var working = subset
        working.move(fromOffsets: plan.fromOffsets, toOffset: plan.toOffset)
        return working
    }

    // MARK: - Case A: homogeneous pages

    /// Dragging pageC to the front of a pages-only list reorders correctly.
    @Test("homogeneous pages: drag last to front yields [C, A, B]")
    func homogeneousPagesDragToFront() throws {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let pageB = pageRow(id: "p-b", title: "Page B")
        let pageC = pageRow(id: "p-c", title: "Page C")
        let rows = [pageA, pageB, pageC]

        let plan = try #require(
            DetailReorderPlanner.plan(rows: rows, movingRowID: "p-c", dropOffset: 0),
            "plan must be non-nil for a valid move"
        )
        #expect(plan.kind == .page)

        let pagesSubset = rows  // all same kind
        let result = applyPlan(plan, to: pagesSubset)
        #expect(result.map(\.id) == ["p-c", "p-a", "p-b"])
    }

    // MARK: - Case B: per-kind scoping (pages don't touch collections)

    /// Dragging pageB to front affects only the pages subset; collections untouched.
    @Test("mixed rows: dragging a page scopes to the pages subset only")
    func dragPageInMixedRows() throws {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let pageB = pageRow(id: "p-b", title: "Page B")
        let collC0 = collectionRow(id: "c-0", title: "Coll C0")
        let collC1 = collectionRow(id: "c-1", title: "Coll C1")
        // display order: pageA, pageB, collC0, collC1
        let rows = [pageA, pageB, collC0, collC1]

        let plan = try #require(
            DetailReorderPlanner.plan(rows: rows, movingRowID: "p-b", dropOffset: 0),
            "plan must be non-nil for a valid move"
        )
        #expect(plan.kind == .page)

        // Apply plan to the PAGES subset only → [B, A]
        let pagesSubset = rows.filter {
            if case .page = $0.kind { return true }
            return false
        }
        let reorderedPages = applyPlan(plan, to: pagesSubset)
        #expect(reorderedPages.map(\.id) == ["p-b", "p-a"])

        // The plan is scoped to the pages subset: its fromOffsets are indices WITHIN
        // that subset (kind == .page routes the move to the pages manager), so every
        // offset is < pagesSubset.count and never lands outside the pages.
        #expect(plan.fromOffsets.allSatisfy { $0 < pagesSubset.count })
    }

    // MARK: - Case C: collections reorder independently

    /// Dragging collC1 to the start of the collections zone reorders only collections.
    @Test("mixed rows: dragging a collection scopes to the collections subset only")
    func dragCollectionInMixedRows() throws {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let pageB = pageRow(id: "p-b", title: "Page B")
        let collC0 = collectionRow(id: "c-0", title: "Coll C0")
        let collC1 = collectionRow(id: "c-1", title: "Coll C1")
        let rows = [pageA, pageB, collC0, collC1]

        // dropOffset 2 = the first collection slot in the flat table
        let plan = try #require(
            DetailReorderPlanner.plan(rows: rows, movingRowID: "c-1", dropOffset: 2),
            "plan must be non-nil for a valid move"
        )
        #expect(plan.kind == .collection)

        // Apply plan to the COLLECTIONS subset only → [C1, C0]
        let collectionsSubset = rows.filter {
            if case .collection = $0.kind { return true }
            return false
        }
        let reorderedCollections = applyPlan(plan, to: collectionsSubset)
        #expect(reorderedCollections.map(\.id) == ["c-1", "c-0"])
    }

    // MARK: - Case D: nil cases

    @Test("dropping a row onto its own position returns nil")
    func noopDropReturnsNil() {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let pageB = pageRow(id: "p-b", title: "Page B")
        let rows = [pageA, pageB]

        // pageA is at index 0; dropping at offset 0 or 1 is its own slot
        #expect(DetailReorderPlanner.plan(rows: rows, movingRowID: "p-a", dropOffset: 0) == nil)
        #expect(DetailReorderPlanner.plan(rows: rows, movingRowID: "p-a", dropOffset: 1) == nil)
    }

    @Test("movingRowID not in rows returns nil")
    func unknownIDReturnsNil() {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let rows = [pageA]
        #expect(DetailReorderPlanner.plan(rows: rows, movingRowID: "ghost", dropOffset: 0) == nil)
    }

    // MARK: - Case E: child (in-collection / in-set) reorder scopes to `kids`

    /// Pins the EXACT call `PageTypeDetailView.handleChildDrop` makes: the inner
    /// ForEach hands the planner the Collection's own children (`kids`) as `rows`,
    /// so the offset math is group-relative — dragging the last Page to the front
    /// yields fromOffsets {2} → toOffset 0, kind .page.
    @Test func childPageReorderWithinCollectionScopesToKids() throws {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let pageB = pageRow(id: "p-b", title: "Page B")
        let pageC = pageRow(id: "p-c", title: "Page C")
        let kids = [pageA, pageB, pageC]

        let plan = try #require(
            DetailReorderPlanner.plan(rows: kids, movingRowID: "p-c", dropOffset: 0),
            "plan must be non-nil for a valid in-collection move"
        )
        #expect(plan.kind == .page)
        #expect(plan.fromOffsets == IndexSet(integer: 2))
        #expect(plan.toOffset == 0)
    }

    /// Item-side mirror: pins the call `ItemTypeDetailView.handleChildDrop` makes.
    @Test func childItemReorderWithinSetScopesToKids() throws {
        let itemA = itemRow(id: "i-a", title: "Item A")
        let itemB = itemRow(id: "i-b", title: "Item B")
        let itemC = itemRow(id: "i-c", title: "Item C")
        let kids = [itemA, itemB, itemC]

        let plan = try #require(
            DetailReorderPlanner.plan(rows: kids, movingRowID: "i-c", dropOffset: 0),
            "plan must be non-nil for a valid in-set move"
        )
        #expect(plan.kind == .item)
        #expect(plan.fromOffsets == IndexSet(integer: 2))
        #expect(plan.toOffset == 0)
    }

    /// Regression guard for the top-level drop after making children draggable:
    /// dragging the COLLECTION parent must still plan as `.collection`, and
    /// dragging a top-level Page must still plan as `.page` — never `.collection`.
    /// (The collection row here carries children, exercising the disclosure shape.)
    @Test func topLevelDragStillKindSafeWithChildrenPresent() throws {
        let pageA = pageRow(id: "p-a", title: "Page A")
        let pageB = pageRow(id: "p-b", title: "Page B")
        let child1 = pageRow(id: "kid-1", title: "Kid 1")
        let child2 = pageRow(id: "kid-2", title: "Kid 2")
        let collX = collectionRow(id: "collection-X", title: "Coll X")
            .withChildren([child1, child2])
        let collY = collectionRow(id: "collection-Y", title: "Coll Y")
        let rows = [pageA, pageB, collX, collY]

        // Dragging the collection parent PAST its sibling → kind .collection. A real
        // move needs two collections to reorder against; a lone collection moved to
        // its own slot is a genuine no-op (planner returns nil by design).
        let collPlan = try #require(
            DetailReorderPlanner.plan(rows: rows, movingRowID: "collection-X", dropOffset: 4),
            "dragging the collection parent must yield a plan"
        )
        #expect(collPlan.kind == .collection)

        // Dragging a top-level Page → kind .page, never .collection.
        let pagePlan = try #require(
            DetailReorderPlanner.plan(rows: rows, movingRowID: "p-b", dropOffset: 0),
            "dragging a top-level page must yield a plan"
        )
        #expect(pagePlan.kind == .page)
    }
}

// MARK: - Test helper

extension DetailRow {
    /// Returns a copy of this row with `children` attached — lets the leaf
    /// fixtures double as disclosure parents in regression tests.
    fileprivate func withChildren(_ kids: [DetailRow]) -> DetailRow {
        DetailRow(
            id: id,
            title: title,
            kind: kind,
            iconName: iconName,
            modifiedAt: modifiedAt,
            children: kids
        )
    }
}
