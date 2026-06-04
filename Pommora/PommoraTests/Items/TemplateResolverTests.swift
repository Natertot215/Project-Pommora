import Testing
import Foundation
@testable import Pommora

@Suite struct TemplateResolverTests {
    private func makeType(_ cfg: ItemTemplateConfig? = nil) -> ItemType {
        ItemType(id: "t1", title: "T", icon: nil, properties: [], views: [], templateConfig: cfg, modifiedAt: .init(timeIntervalSince1970: 0))
    }
    private func makeCollection(_ cfg: ItemTemplateConfig? = nil, pinned: [String] = []) -> ItemCollection {
        ItemCollection(id: "c1", typeID: "t1", title: "C", folderURL: URL(fileURLWithPath: "/tmp/c1"), modifiedAt: .init(timeIntervalSince1970: 0), pinnedProperties: pinned, templateConfig: cfg)
    }
    @Test func collectionOverrideWins() {
        let type = makeType(ItemTemplateConfig(layout: .standard))
        let coll = makeCollection(ItemTemplateConfig(layout: .gallery))
        #expect(TemplateResolver.effective(type: type, collection: coll).layout == .gallery)
    }
    @Test func fallsBackToTypeWhenCollectionConfigNil() {
        let type = makeType(ItemTemplateConfig(layout: .standard))
        #expect(TemplateResolver.effective(type: type, collection: makeCollection(nil)).layout == .standard)
    }
    @Test func nilOnBothYieldsEmptyConfig() {
        let type = makeType(nil)
        #expect(TemplateResolver.effective(type: type, collection: nil) == ItemTemplateConfig())
        #expect(TemplateResolver.effective(type: type, collection: nil).layout == nil)   // callers default to .standard inline
        #expect(TemplateResolver.promoted(type: type, collection: nil) == [])
    }
    @Test func promotedUsesExplicitWhenPresent() {
        let coll = makeCollection(ItemTemplateConfig(promotedProperties: [PromotedProperty(id: "p1", display: .thumbnail)]), pinned: ["legacy"])
        #expect(TemplateResolver.promoted(type: makeType(nil), collection: coll) == [PromotedProperty(id: "p1", display: .thumbnail)])
    }
    @Test func promotedFallsBackToLegacyPinned() {
        let coll = makeCollection(nil, pinned: ["p1","p2"])
        #expect(TemplateResolver.promoted(type: makeType(nil), collection: coll) == [PromotedProperty(id: "p1", display: nil), PromotedProperty(id: "p2", display: nil)])
    }
}
