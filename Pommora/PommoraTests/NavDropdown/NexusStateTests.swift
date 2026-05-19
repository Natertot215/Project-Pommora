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
        #expect(s.favorites.isEmpty)
        #expect(s.cursor == 0)
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        var s = NexusState()
        s.recents = [
            EntityStateRef(kind: .page, id: "01HF", title: "Page A"),
            EntityStateRef(kind: .vault, id: "01HG", title: "Vault B"),
        ]
        s.favorites = [EntityStateRef(kind: .page, id: "01HF", title: "Page A")]
        s.cursor = 1
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(NexusState.self, from: data)
        #expect(decoded.recents.count == 2)
        #expect(decoded.favorites.count == 1)
        #expect(decoded.cursor == 1)
    }

    @Test("decodes legacy file missing favorites/cursor")
    func decodesMissingKeys() throws {
        let json = #"{"schemaVersion":1,"recents":[{"kind":"page","id":"x","title":"y"}]}"#
        let decoded = try JSONDecoder().decode(NexusState.self, from: Data(json.utf8))
        #expect(decoded.recents.count == 1)
        #expect(decoded.favorites.isEmpty)
        #expect(decoded.cursor == 0)
    }
}
