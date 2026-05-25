import Foundation
import Testing

@testable import Pommora

/// Tests for `PageCollectionDetailViewModel` — the sort-state machine backing
/// `PageCollectionDetailView`'s click-to-sort column headers.
///
/// Drives the view-model directly without SwiftUI rendering (J.5/J.11/K.1 pattern).
@Suite("PageCollectionDetailSortTests")
@MainActor
struct PageCollectionDetailSortTests {

    // MARK: - Helpers

    /// Build a DetailRow with controllable title + modifiedAt.
    /// The DetailRow.Kind.page payload is a minimal PageMeta stub;
    /// sort logic never inspects the PageMeta directly — only
    /// DetailRow.title, DetailRow.kindLabel, and DetailRow.modifiedAt.
    private func makeRow(
        id: String,
        title: String,
        modifiedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> DetailRow {
        let fm = PageFrontmatter(
            id: id,
            icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: modifiedAt
        )
        let page = PageMeta(
            id: id,
            title: title,
            url: URL(filePath: "/tmp/\(title).md"),
            frontmatter: fm
        )
        return DetailRow(
            id: id,
            title: title,
            kind: .page(page),
            iconName: "doc.text",
            modifiedAt: modifiedAt,
            children: nil
        )
    }

    // MARK: - Test 1: Initial state — no sort (default)

    @Test("Initial sort column is nil (default order)")
    func initialSortIsDefault() {
        let vm = PageCollectionDetailViewModel()
        #expect(vm.sortColumn == nil)
        #expect(vm.sortAscending == true)
    }

    // MARK: - Test 2: Tapping a column sets it ascending

    @Test("Tapping a column once sets sortColumn ascending")
    func tapColumnOnceAscending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)

        #expect(vm.sortColumn == .name)
        #expect(vm.sortAscending == true)
    }

    // MARK: - Test 3: Second tap on same column → descending

    @Test("Tapping the same column twice sets descending")
    func tapColumnTwiceDescending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)
        vm.tapColumn(.name)

        #expect(vm.sortColumn == .name)
        #expect(vm.sortAscending == false)
    }

    // MARK: - Test 4: Third tap on same column → clear (default)

    @Test("Tapping the same column three times clears sort (back to default)")
    func tapColumnThreeTimesClears() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)
        vm.tapColumn(.name)
        vm.tapColumn(.name)

        #expect(vm.sortColumn == nil)
        #expect(vm.sortAscending == true)
    }

    // MARK: - Test 5: Switching columns resets to ascending on new column

    @Test("Switching to a different column starts ascending on that column")
    func switchingColumnResetsAscending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)
        vm.tapColumn(.name)  // now descending on name
        vm.tapColumn(.modified)  // switch to modified

        #expect(vm.sortColumn == .modified)
        #expect(vm.sortAscending == true)
    }

    // MARK: - Test 6: sorted() preserves order when no column active

    @Test("sorted() returns rows in original order when sortColumn is nil")
    func sortedPreservesOrderWithNoColumn() {
        let vm = PageCollectionDetailViewModel()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let rows = [
            makeRow(id: "r3", title: "Charlie", modifiedAt: base),
            makeRow(id: "r1", title: "Alpha",   modifiedAt: base),
            makeRow(id: "r2", title: "Bravo",   modifiedAt: base),
        ]

        let result = vm.sorted(rows)
        #expect(result.map(\.id) == ["r3", "r1", "r2"])
    }

    // MARK: - Test 7: sorted() by name ascending

    @Test("sorted() by name ascending produces alphabetical order")
    func sortedByNameAscending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)

        let base = Date(timeIntervalSince1970: 1_000_000)
        let rows = [
            makeRow(id: "r3", title: "Charlie", modifiedAt: base),
            makeRow(id: "r1", title: "Alpha",   modifiedAt: base),
            makeRow(id: "r2", title: "Bravo",   modifiedAt: base),
        ]

        let result = vm.sorted(rows)
        #expect(result.map(\.title) == ["Alpha", "Bravo", "Charlie"])
    }

    // MARK: - Test 8: sorted() by name descending

    @Test("sorted() by name descending produces reverse alphabetical order")
    func sortedByNameDescending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)
        vm.tapColumn(.name)  // descending

        let base = Date(timeIntervalSince1970: 1_000_000)
        let rows = [
            makeRow(id: "r3", title: "Charlie", modifiedAt: base),
            makeRow(id: "r1", title: "Alpha",   modifiedAt: base),
            makeRow(id: "r2", title: "Bravo",   modifiedAt: base),
        ]

        let result = vm.sorted(rows)
        #expect(result.map(\.title) == ["Charlie", "Bravo", "Alpha"])
    }

    // MARK: - Test 9: sorted() by modified ascending

    @Test("sorted() by modified ascending produces oldest-first order")
    func sortedByModifiedAscending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.modified)

        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let t1 = Date(timeIntervalSince1970: 1_001_000)
        let t2 = Date(timeIntervalSince1970: 1_002_000)

        let rows = [
            makeRow(id: "r2", title: "B", modifiedAt: t2),
            makeRow(id: "r0", title: "A", modifiedAt: t0),
            makeRow(id: "r1", title: "C", modifiedAt: t1),
        ]

        let result = vm.sorted(rows)
        #expect(result.map(\.id) == ["r0", "r1", "r2"])
    }

    // MARK: - Test 10: indicator returns nil when column is inactive

    @Test("indicator(for:) returns nil for inactive column")
    func indicatorNilForInactiveColumn() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.name)

        #expect(vm.indicator(for: .modified) == nil)
        #expect(vm.indicator(for: .kind) == nil)
    }

    // MARK: - Test 11: indicator returns ▲ for ascending active column

    @Test("indicator(for:) returns ▲ for active ascending column")
    func indicatorUpForAscending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.modified)

        #expect(vm.indicator(for: .modified) == "▲")
    }

    // MARK: - Test 12: indicator returns ▼ for descending active column

    @Test("indicator(for:) returns ▼ for active descending column")
    func indicatorDownForDescending() {
        let vm = PageCollectionDetailViewModel()
        vm.tapColumn(.modified)
        vm.tapColumn(.modified)

        #expect(vm.indicator(for: .modified) == "▼")
    }
}
