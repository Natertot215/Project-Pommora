import Testing
import Foundation
@testable import Pommora

/// Review DRY #5 — `TemplateResolver.promotedEntries` is the single promoted →
/// definition join consumed by BOTH the live renderer (`ItemWindowRenderer.
/// promotedSchema`) and the Templates pane (`ItemTemplatePane.promotedEntries`).
/// It must reproduce the renderer's partition order (promoted order, real ids
/// only) and drop any promoted id with no matching definition — never crash.
@Suite struct PromotedEntriesTests {
    private func def(_ id: String, _ name: String) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: .number)
    }

    private func makeType(properties: [PropertyDefinition], promoted: [PromotedProperty]?) -> ItemType {
        ItemType(
            id: "t1", title: "T", icon: nil,
            properties: properties, views: [],
            templateConfig: ItemTemplateConfig(promotedProperties: promoted),
            modifiedAt: .init(timeIntervalSince1970: 0)
        )
    }

    private func makeCollection(_ cfg: ItemTemplateConfig? = nil, pinned: [String] = []) -> ItemCollection {
        ItemCollection(
            id: "c1", typeID: "t1", title: "C",
            folderURL: URL(fileURLWithPath: "/tmp/c1"),
            modifiedAt: .init(timeIntervalSince1970: 0),
            pinnedProperties: pinned, templateConfig: cfg
        )
    }

    /// The promoted properties join to their definitions, in promoted order.
    @Test func joinsPromotedToDefinitionsInPromotedOrder() {
        let type = makeType(
            properties: [def("a", "A"), def("b", "B"), def("c", "C")],
            promoted: [PromotedProperty(id: "b", display: .thumbnail), PromotedProperty(id: "a", display: nil)]
        )
        let entries = TemplateResolver.promotedEntries(type: type, collection: nil)
        #expect(entries.map(\.promotion.id) == ["b", "a"])
        #expect(entries.map(\.definition.id) == ["b", "a"])
        #expect(entries.map(\.definition.name) == ["B", "A"])
        #expect(entries[0].promotion.display == .thumbnail)
    }

    /// A promoted id with NO matching definition is dropped, not crashed.
    @Test func dropsPromotedIDWithNoMatchingDefinition() {
        let type = makeType(
            properties: [def("a", "A")],
            promoted: [PromotedProperty(id: "a", display: nil), PromotedProperty(id: "ghost", display: nil)]
        )
        let entries = TemplateResolver.promotedEntries(type: type, collection: nil)
        #expect(entries.map(\.promotion.id) == ["a"])
        #expect(entries.count == 1)
    }

    /// The order is the RENDERER's partition order — promoted-first, in promoted
    /// order — NOT the schema order. Here schema order is [a, b, c] but the
    /// promoted order is [c, a]; the helper must emit [c, a]. (This is the case
    /// that would diverge if a call site naively walked schema order.)
    @Test func orderMatchesRendererPartitionNotSchemaOrder() {
        let type = makeType(
            properties: [def("a", "A"), def("b", "B"), def("c", "C")],
            promoted: [PromotedProperty(id: "c", display: nil), PromotedProperty(id: "a", display: nil)]
        )
        let entries = TemplateResolver.promotedEntries(type: type, collection: nil)
        #expect(entries.map(\.definition.id) == ["c", "a"])

        // Cross-check against the renderer's own partition: main ids must equal
        // the helper's ids, proving both surfaces agree.
        let partitionMain = ItemWindowRenderer.partition(
            all: type.properties.map(\.id), promoted: ["c", "a"]
        ).main
        #expect(entries.map(\.definition.id) == partitionMain)
    }

    /// Legacy `pinnedProperties` (no template config) still surfaces, joined and
    /// in pinned order — the pane relied on this before the hoist.
    @Test func legacyPinnedPropertiesSurface() {
        let type = makeType(properties: [def("p1", "P1"), def("p2", "P2")], promoted: nil)
        let coll = makeCollection(nil, pinned: ["p2", "p1"])
        let entries = TemplateResolver.promotedEntries(type: type, collection: coll)
        #expect(entries.map(\.promotion.id) == ["p2", "p1"])
        #expect(entries.map(\.definition.id) == ["p2", "p1"])
    }

    /// No promoted set yields no entries (and never crashes on empty schema).
    @Test func emptyWhenNothingPromoted() {
        let type = makeType(properties: [def("a", "A")], promoted: nil)
        #expect(TemplateResolver.promotedEntries(type: type, collection: nil).isEmpty)
    }
}
