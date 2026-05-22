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
    private let apple = OrderResolverFixture(id: "01-A", title: "Apple")
    private let banana = OrderResolverFixture(id: "02-B", title: "Banana")
    private let cherry = OrderResolverFixture(id: "03-C", title: "Cherry")
    private let date = OrderResolverFixture(id: "04-D", title: "Date")

    @Test func nilPersistedOrderSortsAlphabetically() {
        let items = [cherry, apple, banana]
        let resolved = OrderResolver.resolve(
            items,
            persistedOrder: nil,
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved == [apple, banana, cherry])
    }

    @Test func emptyPersistedOrderSortsAlphabetically() {
        let items = [cherry, apple, banana]
        let resolved = OrderResolver.resolve(
            items,
            persistedOrder: [],
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved == [apple, banana, cherry])
    }

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

    @Test func localizedStandardComparePreservedForNumericTitles() {
        // localizedStandardCompare puts "File 2" before "File 10" — the resolver
        // must keep this behavior to match the pre-v0.2.8 sort.
        let two = OrderResolverFixture(id: "A", title: "File 2")
        let ten = OrderResolverFixture(id: "B", title: "File 10")
        let resolved = OrderResolver.resolve(
            [ten, two],
            persistedOrder: nil,
            titleKeyPath: \OrderResolverFixture.title
        )
        #expect(resolved == [two, ten])
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
