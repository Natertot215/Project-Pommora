import Foundation
import Testing

@testable import Pommora

@Suite("RelationTargetTests") struct RelationTargetTests {
    typealias Target = PropertyDefinition.RelationTarget

    @Test func decodeContextTier() throws {
        let json = #"{"kind": "context_tier", "tier": 2}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Target.self, from: json)
        guard case .contextTier(let tier) = s else {
            #expect(Bool(false), "expected .contextTier, got \(s)")
            return
        }
        #expect(tier == 2)
    }

    @Test func encodeContextTier() throws {
        let s: Target = .contextTier(3)
        let data = try JSONEncoder().encode(s)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains(#""kind":"context_tier""#))
        #expect(str.contains(#""tier":3"#))
    }

    @Test func roundTripContextTier() throws {
        let target: Target = .contextTier(1)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: data)
        #expect(decoded == target)
    }

    @Test func decodeUnknownKindThrows() throws {
        let json = #"{"kind": "galaxy_brain", "id": "x"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Target.self, from: json)
        }
    }

    @Test func legacyStringScopeIsRejected() throws {
        // Pre-v0.3.0 schemas used bare-string enum form ("same_vault" / "anywhere").
        let json = #""same_vault""#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Target.self, from: json)
        }
    }

    // MARK: - Tolerant decode regression: retired user-target degrades to nil in PropertyDefinition

    @Test func retiredPageTypeTargetDegradesPropertyDefinitionToNilRelationTarget() throws {
        // A sidecar JSON carrying a page_type relation_target must decode successfully
        // (the sidecar LOADS); the def's relationTarget becomes nil (tolerance boundary).
        let json = """
            {
                "id": "prop_01HRET",
                "name": "Legacy",
                "type": "relation",
                "relation_target": {"kind": "page_type", "page_type_id": "X"}
            }
            """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: json)
        #expect(decoded.id == "prop_01HRET")
        #expect(decoded.type == .relation)
        #expect(decoded.relationTarget == nil)
    }
}
