//
//  GalleryCardZonesTests.swift
//  PommoraTests
//
//  Pure-value coverage for the gallery card's zone partition + the gallery
//  renderer's vault-scope flatten guarantee. No disk, no SwiftUI.
//

import Foundation
import Testing

@testable import Pommora

@Suite struct GalleryCardZonesTests {

    // MARK: - Schema fixtures (one of each zone-relevant type)

    private func def(_ id: String, _ type: PropertyType) -> PropertyDefinition {
        PropertyDefinition(id: id, name: id, type: type)
    }

    /// One property per type so every zone bucket is exercised in a single run.
    private var fullSchema: [PropertyDefinition] {
        [
            def("p_select", .select),
            def("p_multi", .multiSelect),
            def("p_status", .status),
            def("p_relation", .relation),
            def("p_date", .date),
            def("p_datetime", .datetime),
            def("p_modified", .lastEditedTime),
            def("p_number", .number),
            def("p_checkbox", .checkbox),
            def("p_url", .url),
        ]
    }

    private func view(
        order: [String] = [], hidden: [String] = []
    ) -> SavedView {
        SavedView(
            id: "view_1", type: .gallery,
            propertyOrder: order, hiddenProperties: hidden
        )
    }

    // MARK: - Zone bucketing

    @Test func chipsZoneHoldsSelectMultiStatusRelation() {
        let parts = GalleryCardZones.partition(view: view(), schema: fullSchema)
        let chipIDs = parts.chips.map(\.id)
        #expect(chipIDs.contains("p_select"))
        #expect(chipIDs.contains("p_multi"))
        #expect(chipIDs.contains("p_status"))
        #expect(chipIDs.contains("p_relation"))
        // None of the non-chip types leak in.
        #expect(!chipIDs.contains("p_number"))
        #expect(!chipIDs.contains("p_url"))
    }

    @Test func metaZoneHoldsDateDatetimeModifiedNumberCheckbox() {
        let parts = GalleryCardZones.partition(view: view(), schema: fullSchema)
        let metaIDs = parts.meta.map(\.id)
        #expect(metaIDs.contains("p_date"))
        #expect(metaIDs.contains("p_datetime"))
        #expect(metaIDs.contains("p_modified"))
        #expect(metaIDs.contains("p_number"))
        #expect(metaIDs.contains("p_checkbox"))
    }

    @Test func linksZoneHoldsURL() {
        let parts = GalleryCardZones.partition(view: view(), schema: fullSchema)
        #expect(parts.links.map(\.id) == ["p_url"])
    }

    @Test func zoneMappingIsExhaustive() {
        #expect(GalleryCardZones.zone(for: .select) == .chips)
        #expect(GalleryCardZones.zone(for: .multiSelect) == .chips)
        #expect(GalleryCardZones.zone(for: .status) == .chips)
        #expect(GalleryCardZones.zone(for: .relation) == .chips)
        #expect(GalleryCardZones.zone(for: .date) == .meta)
        #expect(GalleryCardZones.zone(for: .datetime) == .meta)
        #expect(GalleryCardZones.zone(for: .lastEditedTime) == .meta)
        #expect(GalleryCardZones.zone(for: .number) == .meta)
        #expect(GalleryCardZones.zone(for: .checkbox) == .meta)
        #expect(GalleryCardZones.zone(for: .url) == .links)
    }

    // MARK: - Exclusions

    @Test func coverFieldNeverAppears() {
        let schema = fullSchema + [def("cover", .url)]
        let parts = GalleryCardZones.partition(
            view: view(order: ["cover", "p_url"]), schema: schema)
        let allIDs = (parts.chips + parts.meta + parts.links).map(\.id)
        #expect(!allIDs.contains("cover"))
    }

    @Test func titleFieldNeverAppears() {
        let schema = fullSchema + [def(ReservedPropertyID.title, .select)]
        let parts = GalleryCardZones.partition(
            view: view(order: [ReservedPropertyID.title, "p_select"]), schema: schema)
        let allIDs = (parts.chips + parts.meta + parts.links).map(\.id)
        #expect(!allIDs.contains(ReservedPropertyID.title))
    }

    @Test func hiddenPropertiesRespected() {
        let parts = GalleryCardZones.partition(
            view: view(hidden: ["p_select", "p_url"]), schema: fullSchema)
        let allIDs = (parts.chips + parts.meta + parts.links).map(\.id)
        #expect(!allIDs.contains("p_select"))
        #expect(!allIDs.contains("p_url"))
        // A non-hidden one survives.
        #expect(allIDs.contains("p_number"))
    }

    // MARK: - Ordering

    @Test func orderVerbatimThenUnaccountedAppend() {
        // Order lists number + url first (reversed vs. schema); the rest append
        // in schema order after them.
        let order = ["p_number", "p_url"]
        let visible = GalleryCardZones.visibleProperties(
            view: view(order: order), schema: fullSchema)
        let ids = visible.map(\.id)
        #expect(ids.first == "p_number")
        #expect(ids[1] == "p_url")
        // Every schema property is accounted for exactly once.
        #expect(Set(ids) == Set(fullSchema.map(\.id)))
        #expect(ids.count == fullSchema.count)
    }

    // MARK: - Vault-scope flatten lossless guarantee

    @Test func flattenedItemsLosesNoSetPage() {
        let coll = VPFixture.collection("coll_1", title: "Coll")
        let setA = VPFixture.set("set_a", title: "Set A", collection: "coll_1")
        let setB = VPFixture.set("set_b", title: "Set B", collection: "coll_1")

        // A Collection group with 2 loose pages + 2 nested Set children, each
        // holding pages. flattenedItems must surface ALL of them.
        let setGroupA = ResolvedGroup(
            id: setA.id, title: setA.title, kind: .structuralSet(setA),
            items: [
                VPFixture.item("p3", title: "P3", in: setA, of: coll),
                VPFixture.item("p4", title: "P4", in: setA, of: coll),
            ])
        let setGroupB = ResolvedGroup(
            id: setB.id, title: setB.title, kind: .structuralSet(setB),
            items: [VPFixture.item("p5", title: "P5", in: setB, of: coll)])
        let collGroup = ResolvedGroup(
            id: coll.id, title: coll.title, kind: .structuralCollection(coll),
            items: [
                VPFixture.item("p1", title: "P1", in: coll),
                VPFixture.item("p2", title: "P2", in: coll),
            ],
            children: [setGroupA, setGroupB])

        let flattened = collGroup.flattenedItems
        #expect(flattened.count == 5)
        #expect(Set(flattened.map(\.id)) == ["p1", "p2", "p3", "p4", "p5"])
    }

    @Test func flattenedItemsEmptyChildrenJustOwnItems() {
        let coll = VPFixture.collection("coll_2", title: "Coll2")
        let group = ResolvedGroup(
            id: coll.id, title: coll.title, kind: .structuralCollection(coll),
            items: [VPFixture.item("only", title: "Only", in: coll)])
        #expect(group.flattenedItems.map(\.id) == ["only"])
    }
}
