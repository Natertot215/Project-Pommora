//
//  SortComparatorTests.swift
//  PommoraTests
//
//  Pure-logic tests for the view-pipeline sort engine. No disk.
//

import Foundation
import Testing

@testable import Pommora

struct SortComparatorTests {
    private let coll = VPFixture.collection("coll_1", title: "Coll")

    private func crit(_ id: String, _ dir: SortDirection) -> SortCriterion {
        SortCriterion(propertyID: id, direction: dir)
    }

    /// Applies a comparator to items the way the pipeline does (stable sort);
    /// returns nil-passthrough when the comparator is nil.
    private func order(_ items: [ViewItem], by comparator: ViewSortComparator.Comparator?) -> [String] {
        guard let comparator else { return items.map(\.id) }
        return items.enumerated()
            .sorted {
                if comparator($0.element, $1.element) { return true }
                if comparator($1.element, $0.element) { return false }
                return $0.offset < $1.offset
            }
            .map(\.element.id)
    }

    // MARK: - Manual (nil)

    @Test func nilCriterionIsManual() {
        #expect(ViewSortComparator.comparator(for: nil, schema: []) == nil)
    }

    // MARK: - Title

    @Test func titleSortIsCaseInsensitiveAscending() {
        let a = VPFixture.item("01", title: "banana", in: coll)
        let b = VPFixture.item("02", title: "Apple", in: coll)
        let c = VPFixture.item("03", title: "cherry", in: coll)
        let cmp = ViewSortComparator.comparator(for: crit("_title", .ascending), schema: [])
        #expect(order([a, b, c], by: cmp) == ["02", "01", "03"])
    }

    @Test func titleSortDescendingFlips() {
        let a = VPFixture.item("01", title: "Apple", in: coll)
        let b = VPFixture.item("02", title: "banana", in: coll)
        let cmp = ViewSortComparator.comparator(for: crit("_title", .descending), schema: [])
        #expect(order([a, b], by: cmp) == ["02", "01"])
    }

    // MARK: - ID (ULID = creation order)

    @Test func idSortIsLexicographic() {
        let older = VPFixture.item("01HAAA", title: "Zebra", in: coll)
        let newer = VPFixture.item("01HBBB", title: "Apple", in: coll)
        let cmp = ViewSortComparator.comparator(for: crit("_id", .ascending), schema: [])
        // id order wins over title.
        #expect(order([newer, older], by: cmp) == ["01HAAA", "01HBBB"])
    }

    // MARK: - Modified-at with createdAt fallback

    @Test func modifiedSortUsesCreatedAtFallbackWhenNil() {
        // p1 has explicit modified far in the future; p2 has nil modified but an
        // early createdAt → ascending order is [p2, p1].
        let p1 = ViewItem(
            page: VPFixture.meta(
                id: "p1", title: "P1",
                createdAt: VPFixture.date("2000-01-01T00:00:00Z"),
                modifiedAt: VPFixture.date("2030-01-01T00:00:00Z")),
            parent: .collection(coll, vault: VPFixture.vault()), setLabel: nil)
        let p2 = ViewItem(
            page: VPFixture.meta(
                id: "p2", title: "P2",
                createdAt: VPFixture.date("2010-01-01T00:00:00Z"),
                modifiedAt: nil),
            parent: .collection(coll, vault: VPFixture.vault()), setLabel: nil)
        let asc = ViewSortComparator.comparator(for: crit("_modified_at", .ascending), schema: [])
        #expect(order([p1, p2], by: asc) == ["p2", "p1"])
        let desc = ViewSortComparator.comparator(for: crit("_modified_at", .descending), schema: [])
        #expect(order([p1, p2], by: desc) == ["p1", "p2"])
    }

    // MARK: - Select by schema option order (not alphabetic)

    @Test func selectSortsBySchemaOptionOrderNotAlphabetic() {
        // Option order: high, medium, low — deliberately NON-alphabetic.
        let def = VPFixture.selectDef(
            "prop_p", name: "Priority",
            options: [("high", "High"), ("medium", "Medium"), ("low", "Low")])
        let a = VPFixture.item("a", title: "A", in: coll, properties: ["prop_p": .select("low")])
        let b = VPFixture.item("b", title: "B", in: coll, properties: ["prop_p": .select("high")])
        let c = VPFixture.item("c", title: "C", in: coll, properties: ["prop_p": .select("medium")])
        let cmp = ViewSortComparator.comparator(for: crit("prop_p", .ascending), schema: [def])
        // Option order high → medium → low: [b, c, a]. Alphabetic would be high,low,medium.
        #expect(order([a, b, c], by: cmp) == ["b", "c", "a"])
    }

    @Test func unknownPropertyCriterionIsManual() {
        // No schema entry → nil comparator (manual).
        #expect(ViewSortComparator.comparator(for: crit("prop_missing", .ascending), schema: []) == nil)
    }
}
