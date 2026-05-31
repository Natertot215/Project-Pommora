//
//  OrderResolverTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

private struct OrderResolverFixture: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
}

struct OrderResolverTests {
    // id order: apple < banana < cherry < date (lexicographic = creation order).
    // title order matches id order for these fixtures — used by the persisted-path
    // tests where creation order is irrelevant.
    private let apple = OrderResolverFixture(id: "01-A", title: "Apple")
    private let banana = OrderResolverFixture(id: "02-B", title: "Banana")
    private let cherry = OrderResolverFixture(id: "03-C", title: "Cherry")
    private let date = OrderResolverFixture(id: "04-D", title: "Date")

    // MARK: - Empty-state fallback: creation (ULID-id ascending) order

    // Discriminating fixtures: id order and title order deliberately DISAGREE.
    // older.id < newer.id  →  older was created first.
    // older.title ("Zebra") > newer.title ("Apple")  →  alphabetical would put newer first.
    // Creation-order must return [older, newer]; alphabetical would return [newer, older].
    private let older = OrderResolverFixture(
        id: "01HZZZZZZZZZZZZZZZZZZZZZ001", title: "Zebra"
    )
    private let newer = OrderResolverFixture(
        id: "01HZZZZZZZZZZZZZZZZZZZZZ002", title: "Apple"
    )

    @Test func nilPersistedOrderSortsByCreationOrder() {
        // RED proof: old `alphabetic` fallback returns [newer(Apple), older(Zebra)]
        // because "Apple" < "Zebra". New ULID-id fallback must return [older, newer]
        // because older.id < newer.id.
        let result = OrderResolver.resolve(
            [newer, older],
            persistedOrder: nil,
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(result.map(\.id) == [older.id, newer.id])
    }

    @Test func emptyPersistedOrderSortsByCreationOrder() {
        // Same discrimination via empty array instead of nil.
        // OLD output: [newer(Apple), older(Zebra)].  NEW output: [older, newer].
        let result = OrderResolver.resolve(
            [newer, older],
            persistedOrder: [],
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(result.map(\.id) == [older.id, newer.id])
    }

    @Test func creationOrderIsOldestFirst() {
        // Three items whose titles are reverse-alphabetical to their id order.
        // Creation (ULID-id) order must win: A → B → C.
        let a = OrderResolverFixture(id: "01HZZZZZZZZZZZZZZZZZZZZZ001", title: "Zebra")
        let b = OrderResolverFixture(id: "01HZZZZZZZZZZZZZZZZZZZZZ002", title: "Mango")
        let c = OrderResolverFixture(id: "01HZZZZZZZZZZZZZZZZZZZZZ003", title: "Apple")
        let result = OrderResolver.resolve(
            [c, a, b],
            persistedOrder: nil,
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(result == [a, b, c])
    }

    // MARK: - Persisted-order path (unchanged)

    @Test func fullPersistedOrderHonoredExactly() {
        let items = [apple, banana, cherry]
        let resolved = OrderResolver.resolve(
            items,
            persistedOrder: [cherry.id, apple.id, banana.id],
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved == [cherry, apple, banana])
    }

    @Test func tombstonesInPersistedOrderAreFiltered() {
        // persistedOrder references a deleted entity ID "DELETED-ID"; resolver
        // should skip it and return only the surviving entities in their
        // persisted positions.
        let items = [apple, banana, cherry]
        let resolved = OrderResolver.resolve(
            items,
            persistedOrder: [cherry.id, "DELETED-ID", apple.id, banana.id],
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved == [cherry, apple, banana])
    }

    @Test func unknownEntitiesAreAppendedAlphabetically() {
        // persistedOrder mentions only apple + cherry; banana and date are
        // "new arrivals" that must land at the end, sorted alphabetically
        // among themselves (banana before date).
        let items = [apple, banana, cherry, date]
        let resolved = OrderResolver.resolve(
            items,
            persistedOrder: [cherry.id, apple.id],
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved == [cherry, apple, banana, date])
    }

    @Test func unknownEntitiesAppendedWithNumericAwareSorting() {
        // localizedStandardCompare puts "File 2" before "File 10";
        // plain `<` (byte order) would invert them ("File 10" < "File 2").
        // This pins the persisted-tail sort against the numeric-aware path
        // that was retained in OrderResolver after the empty-state fallback
        // changed from alphabetical to creation-order.
        let file2 = OrderResolverFixture(id: "02-B", title: "File 2")
        let file10 = OrderResolverFixture(id: "03-C", title: "File 10")
        let anchor = OrderResolverFixture(id: "01-A", title: "Anchor")
        let resolved = OrderResolver.resolve(
            [file10, file2, anchor],
            persistedOrder: [anchor.id],
            titleKeyPath: \OrderResolverFixture.title
        )
        // anchor is persisted-first; file2 + file10 are unknown tail,
        // numeric-aware sort puts "File 2" before "File 10".
        #expect(resolved == [anchor, file2, file10])
    }

    @Test func resolverIsIdempotent() {
        let items = [cherry, apple, banana]
        let order = [banana.id, cherry.id, apple.id]
        let once = OrderResolver.resolve(
            items, persistedOrder: order, titleKeyPath: \OrderResolverFixture.title
        )
        let twice = OrderResolver.resolve(
            once, persistedOrder: order, titleKeyPath: \OrderResolverFixture.title
        )
        #expect(once == twice)
    }

    @Test func emptyItemsReturnsEmpty() {
        let resolved = OrderResolver.resolve(
            [OrderResolverFixture](),
            persistedOrder: ["A", "B", "C"],
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved.isEmpty)
    }
}
