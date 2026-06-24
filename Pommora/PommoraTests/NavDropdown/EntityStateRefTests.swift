// EntityStateRefTests.swift
import Foundation
import Testing

@testable import Pommora

@Suite("EntityStateRef")
struct EntityStateRefTests {
    @Test("encodes to flat JSON shape")
    func encodesToFlatShape() throws {
        let ref = EntityStateRef(kind: "page", id: "01HF", title: "Stoic Reflections")
        let data = try JSONEncoder().encode(ref)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["kind": "page", "id": "01HF", "title": "Stoic Reflections"])
    }

    @Test("decodes from flat JSON shape")
    func decodesFromFlatShape() throws {
        let json = #"{"kind":"vault","id":"01HG","title":"Reading List"}"#
        let ref = try JSONDecoder().decode(EntityStateRef.self, from: Data(json.utf8))
        #expect(ref.kind == "vault")
        #expect(ref.id == "01HG")
        #expect(ref.title == "Reading List")
    }

    @Test("typedKind returns enum for known kinds")
    func typedKindKnown() {
        #expect(EntityStateRef(kind: "page", id: "x", title: "y").typedKind == .page)
        #expect(EntityStateRef(kind: "agenda", id: "x", title: "y").typedKind == .agenda)
    }

    @Test("typedKind returns nil for unknown kinds (forward-compat)")
    func typedKindUnknown() {
        #expect(EntityStateRef(kind: "wormhole", id: "x", title: "y").typedKind == nil)
    }

    @Test("equality + hash by (kind, id)")
    func equalityByKindAndID() {
        let a = EntityStateRef(kind: "page", id: "01HF", title: "Original")
        let b = EntityStateRef(kind: "page", id: "01HF", title: "Renamed")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("legacy 'vault' kind decodes as .collection (top tier)")
    func legacyCollectionKindMapsToCollection() {
        // Pre-Phase-3 state.json wrote the top container as "vault".
        #expect(EntityStateRef(kind: "vault", id: "x", title: "y").typedKind == .collection)
    }

    @Test("new container kinds resolve: collection (top) + set (depth-1)")
    func newContainerKinds() {
        #expect(EntityStateRef(kind: .collection, id: "x", title: "y").typedKind == .collection)
        #expect(EntityStateRef(kind: .set, id: "x", title: "y").typedKind == .set)
    }
}
