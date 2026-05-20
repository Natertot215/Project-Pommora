// NexusStateTests.swift
import Foundation
import Testing

@testable import Pommora

@Suite("NexusState")
struct NexusStateTests {
    @Test("default initializes empty with schemaVersion 1")
    func defaultEmpty() {
        let s = NexusState()
        #expect(s.schemaVersion == 1)
        #expect(s.recents.isEmpty)
        #expect(s.pinned.isEmpty)
        #expect(s.cursor == 0)
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        var s = NexusState()
        s.recents = [
            EntityStateRef(kind: .page, id: "01HF", title: "Page A"),
            EntityStateRef(kind: .vault, id: "01HG", title: "Vault B"),
        ]
        s.pinned = [EntityStateRef(kind: .page, id: "01HF", title: "Page A")]
        s.cursor = 1
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(NexusState.self, from: data)
        #expect(decoded.recents.count == 2)
        #expect(decoded.pinned.count == 1)
        #expect(decoded.cursor == 1)
    }

    @Test("decodes legacy file missing pinned/cursor")
    func decodesMissingKeys() throws {
        let json = #"{"schemaVersion":1,"recents":[{"kind":"page","id":"x","title":"y"}]}"#
        let decoded = try JSONDecoder().decode(NexusState.self, from: Data(json.utf8))
        #expect(decoded.recents.count == 1)
        #expect(decoded.pinned.isEmpty)
        #expect(decoded.cursor == 0)
    }

    @Test("decodes legacy 'favorites' key into pinned (backward-compat)")
    func decodesLegacyFavoritesKey() throws {
        // state.json files written before v0.2.7.2.1 used "favorites" as the
        // top-level key. The decoder falls back to the legacy key so users
        // don't lose pinned entries on first launch after the rename.
        let json =
            #"{"schemaVersion":1,"recents":[],"favorites":[{"kind":"page","id":"P1","title":"Pinned 1"},{"kind":"vault","id":"V1","title":"Pinned Vault"}]}"#
        let decoded = try JSONDecoder().decode(NexusState.self, from: Data(json.utf8))
        #expect(decoded.pinned.count == 2)
        #expect(decoded.pinned.first?.id == "P1")
        #expect(decoded.pinned.last?.id == "V1")
    }

    @Test("encoder writes only 'pinned' (legacy 'favorites' key not emitted)")
    func encoderWritesOnlyPinnedKey() throws {
        var s = NexusState()
        s.pinned = [EntityStateRef(kind: .page, id: "P1", title: "Pinned 1")]
        let data = try JSONEncoder().encode(s)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"pinned\""))
        #expect(!json.contains("\"favorites\""))
    }
}
