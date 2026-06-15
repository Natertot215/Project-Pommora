import Foundation
import Testing
@testable import Pommora

@Suite("GroupResolverDateTests") struct GroupResolverDateTests {
    private let coll = VPFixture.collection("coll_1", title: "Notes")

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("two dates in the same month land in one bucket; different months yield separate buckets")
    func dateBucketsByMonth() {
        let items = [
            VPFixture.item("p1", title: "A", in: coll,
                properties: ["prop_due": .date(date(2026, 6, 1))]),
            VPFixture.item("p2", title: "B", in: coll,
                properties: ["prop_due": .date(date(2026, 6, 30))]),
            VPFixture.item("p3", title: "C", in: coll,
                properties: ["prop_due": .date(date(2026, 7, 15))]),
        ]
        let grouping = PropertyGrouping(
            propertyID: "prop_due",
            orderMode: .configured,
            order: nil,
            dateGranularity: .month
        )
        let dateDef = VPFixture.dateDef("prop_due", name: "Due")
        let groups = GroupResolver.resolve(
            items: items,
            config: .property(grouping),
            scope: .collection,
            schema: [dateDef]
        )

        // Expect "2026-06" (p1+p2) and "2026-07" (p3).
        let bucketIDs = groups.filter { $0.id != GroupResolver.ungroupedID }.map(\.id)
        #expect(bucketIDs.contains("2026-06"))
        #expect(bucketIDs.contains("2026-07"))
        let juneBucket = groups.first(where: { $0.id == "2026-06" })
        #expect(juneBucket?.items.count == 2)
        let julyBucket = groups.first(where: { $0.id == "2026-07" })
        #expect(julyBucket?.items.count == 1)
    }

    @Test("datetime values bucket identically to date values at month granularity")
    func datetimeBucketsByMonth() {
        let items = [
            VPFixture.item("p1", title: "A", in: coll,
                properties: ["prop_due": .datetime(date(2026, 3, 10))]),
            VPFixture.item("p2", title: "B", in: coll,
                properties: ["prop_due": .datetime(date(2026, 4, 20))]),
        ]
        let grouping = PropertyGrouping(
            propertyID: "prop_due",
            orderMode: .configured,
            order: nil,
            dateGranularity: .month
        )
        let dateDef = VPFixture.dateDef("prop_due", name: "Due")
        let groups = GroupResolver.resolve(
            items: items,
            config: .property(grouping),
            scope: .collection,
            schema: [dateDef]
        )
        let bucketIDs = groups.filter { $0.id != GroupResolver.ungroupedID }.map(\.id)
        #expect(bucketIDs.contains("2026-03"))
        #expect(bucketIDs.contains("2026-04"))
        #expect(groups.count == 2)
    }

    @Test("items with no date value land in the ungrouped bucket")
    func noDateValueIsUngrouped() {
        let items = [
            VPFixture.item("p1", title: "A", in: coll,
                properties: ["prop_due": .date(date(2026, 6, 1))]),
            VPFixture.item("p2", title: "B", in: coll),
        ]
        let grouping = PropertyGrouping(
            propertyID: "prop_due",
            orderMode: .configured,
            order: nil,
            dateGranularity: .month
        )
        let dateDef = VPFixture.dateDef("prop_due", name: "Due")
        let groups = GroupResolver.resolve(
            items: items,
            config: .property(grouping),
            scope: .collection,
            schema: [dateDef]
        )
        let ungrouped = groups.first(where: { $0.id == GroupResolver.ungroupedID })
        #expect(ungrouped != nil)
        #expect(ungrouped?.items.count == 1)
    }
}
