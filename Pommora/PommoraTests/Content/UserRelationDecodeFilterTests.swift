import Foundation
import Testing

@testable import Pommora

@Suite("UserRelationDecodeFilter")
struct UserRelationDecodeFilterTests {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test func itemTypeDropsUserRelationDefOnDecode() throws {
        let json = """
            {"id":"01ITEMTYPE","modified_at":"2026-06-04T00:00:00Z","schema_version":2,
             "properties":[{"id":"prop_rel","name":"Author","type":"relation","relation_target":{"kind":"item_type","item_type_id":"01OTHER"}},
                           {"id":"prop_num","name":"Pages","type":"number"}]}
            """
        let t = try decoder().decode(ItemType.self, from: Data(json.utf8))
        #expect(t.properties.contains { $0.id == "prop_num" })
        #expect(!t.properties.contains { $0.type == .relation })
    }

    @Test func pageTypeDropsUserRelationDefOnDecode() throws {
        let json = """
            {"id":"01PAGETYPE","modified_at":"2026-06-04T00:00:00Z","schema_version":2,
             "properties":[{"id":"prop_rel","name":"Cited","type":"relation","relation_target":{"kind":"page_type","page_type_id":"01OTHER"}}]}
            """
        #expect(try decoder().decode(PageType.self, from: Data(json.utf8)).properties.isEmpty)
    }

    // CRITICAL: a stored tier override (reserved id, type .relation) MUST survive — these carry custom reverse-name/icon.
    @Test func itemTypeKeepsStoredTierOverrideOnDecode() throws {
        let json = """
            {"id":"01ITEMTYPE","modified_at":"2026-06-04T00:00:00Z","schema_version":2,
             "properties":[{"id":"_tier1","name":"My Spaces","type":"relation","relation_target":{"kind":"context_tier","tier":1},"reverse_name":"Members"}]}
            """
        let t = try decoder().decode(ItemType.self, from: Data(json.utf8))
        let tier = try #require(t.properties.first { $0.id == "_tier1" })
        #expect(tier.reverseName == "Members")
    }
}
