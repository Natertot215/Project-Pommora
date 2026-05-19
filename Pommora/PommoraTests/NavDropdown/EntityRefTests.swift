import Foundation
import Testing

@testable import Pommora

@Suite("EntityRef")
struct EntityRefTests {
    @Test("page case carries IDs")
    func pageCase() {
        let ref = EntityRef.page(pageID: "p1", vaultID: "v1", collectionID: "c1")
        if case .page(let pageID, let vaultID, let collectionID) = ref {
            #expect(pageID == "p1")
            #expect(vaultID == "v1")
            #expect(collectionID == "c1")
        } else {
            Issue.record("expected .page case")
        }
    }

    @Test("Hashable identity matches by case + payload")
    func hashableIdentity() {
        let a = EntityRef.page(pageID: "p1", vaultID: "v1", collectionID: nil)
        let b = EntityRef.page(pageID: "p1", vaultID: "v1", collectionID: nil)
        let c = EntityRef.page(pageID: "p1", vaultID: "v1", collectionID: "c1")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable round-trip preserves all cases")
    func codableRoundTrip() throws {
        let cases: [EntityRef] = [
            .page(pageID: "p1", vaultID: "v1", collectionID: "c1"),
            .page(pageID: "p2", vaultID: "v2", collectionID: nil),
            .vault(vaultID: "v3"),
            .space(spaceID: "s1"),
            .topic(topicID: "t1"),
            .subtopic(subtopicID: "st1", parentTopicID: "t1"),
        ]
        for ref in cases {
            let data = try JSONEncoder().encode(ref)
            let decoded = try JSONDecoder().decode(EntityRef.self, from: data)
            #expect(decoded == ref)
        }
    }
}
