import Foundation
import Testing
@testable import Pommora

@Suite("RelationScope") struct RelationScopeTests {
    typealias Scope = PropertyDefinition.RelationScope

    @Test func decodePageTypeScope() throws {
        let json = #"{"kind": "page_type", "page_type_id": "01HPAGETYPE"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Scope.self, from: json)
        guard case let .pageType(id) = s else {
            #expect(Bool(false), "expected .pageType, got \(s)")
            return
        }
        #expect(id == "01HPAGETYPE")
    }

    @Test func decodeItemTypeScope() throws {
        let json = #"{"kind": "item_type", "item_type_id": "01HITEMTYPE"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Scope.self, from: json)
        guard case let .itemType(id) = s else {
            #expect(Bool(false), "expected .itemType, got \(s)")
            return
        }
        #expect(id == "01HITEMTYPE")
    }

    @Test func decodePageCollectionScope() throws {
        let json = #"{"kind": "page_collection", "page_collection_id": "01HPC"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Scope.self, from: json)
        guard case let .pageCollection(id) = s else {
            #expect(Bool(false), "expected .pageCollection, got \(s)")
            return
        }
        #expect(id == "01HPC")
    }

    @Test func decodeItemCollectionScope() throws {
        let json = #"{"kind": "item_collection", "item_collection_id": "01HIC"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Scope.self, from: json)
        guard case let .itemCollection(id) = s else {
            #expect(Bool(false), "expected .itemCollection, got \(s)")
            return
        }
        #expect(id == "01HIC")
    }

    @Test func decodeContextTier() throws {
        let json = #"{"kind": "context_tier", "tier": 2}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Scope.self, from: json)
        guard case let .contextTier(tier) = s else {
            #expect(Bool(false), "expected .contextTier, got \(s)")
            return
        }
        #expect(tier == 2)
    }

    @Test func encodePageType() throws {
        let s: Scope = .pageType("01HPAGETYPE")
        let data = try JSONEncoder().encode(s)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains(#""kind":"page_type""#))
        #expect(str.contains(#""page_type_id":"01HPAGETYPE""#))
    }

    @Test func encodeContextTier() throws {
        let s: Scope = .contextTier(3)
        let data = try JSONEncoder().encode(s)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains(#""kind":"context_tier""#))
        #expect(str.contains(#""tier":3"#))
    }

    @Test func roundTripAllFiveCases() throws {
        let cases: [Scope] = [
            .pageType("01H1"),
            .itemType("01H2"),
            .pageCollection("01H3"),
            .itemCollection("01H4"),
            .contextTier(1),
        ]
        for s in cases {
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(Scope.self, from: data)
            #expect(decoded == s)
        }
    }

    @Test func decodeUnknownKindThrows() throws {
        let json = #"{"kind": "galaxy_brain", "id": "x"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Scope.self, from: json)
        }
    }

    @Test func legacyStringScopeIsRejected() throws {
        // Pre-v0.3.0 schemas used bare-string enum form ("same_vault" / "anywhere").
        // These now fail to decode; the adoption-pass migration is expected to
        // rewrite them to the new tagged-object shape (or surface as broken-schema
        // toast per L21).
        let json = #""same_vault""#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Scope.self, from: json)
        }
    }
}
