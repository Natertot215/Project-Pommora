//
//  AppStateTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

struct AppStateTests {
    @Test func defaultInitializerSetsSchemaVersion2() {
        let state = AppState()
        #expect(state.schemaVersion == 2)  // bumped v0.2.7 for pageInspectorOpen
        #expect(state.lastNexusBookmark == nil)
        #expect(state.pageInspectorOpen.isEmpty)
    }

    @Test func roundTripPreservesPageInspectorOpen() throws {
        let original = AppState(
            schemaVersion: 2,
            lastNexusBookmark: nil,
            pageInspectorOpen: ["01HABC": true, "01HXYZ": false]
        )
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try original.save(to: url)
        let loaded = try AppState.load(from: url)

        #expect(loaded == original)
        #expect(loaded.pageInspectorOpen["01HABC"] == true)
        #expect(loaded.pageInspectorOpen["01HXYZ"] == false)
    }

    @Test func decodesV1FileWithMissingPageInspectorOpenKey() throws {
        // v1 schema only had schemaVersion + lastNexusBookmark. Decoding that
        // shape should produce an AppState with empty pageInspectorOpen, not
        // throw a missing-key error.
        let v1JSON = """
            {"schemaVersion": 1}
            """
        let data = Data(v1JSON.utf8)
        let loaded = try JSONDecoder().decode(AppState.self, from: data)

        #expect(loaded.schemaVersion == 1)
        #expect(loaded.lastNexusBookmark == nil)
        #expect(loaded.pageInspectorOpen.isEmpty)
    }

    @Test func roundTripWithNilBookmark() throws {
        let original = AppState(schemaVersion: 1, lastNexusBookmark: nil)
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try original.save(to: url)
        let loaded = try AppState.load(from: url)

        #expect(loaded == original)
    }

    @Test func roundTripWithBookmarkData() throws {
        let bookmark = Data((0..<256).map { UInt8($0) })
        let original = AppState(schemaVersion: 1, lastNexusBookmark: bookmark)
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try original.save(to: url)
        let loaded = try AppState.load(from: url)

        #expect(loaded.schemaVersion == 1)
        #expect(loaded.lastNexusBookmark == bookmark)
    }

    @Test func savedFileIsValidJSON() throws {
        let state = AppState(schemaVersion: 1, lastNexusBookmark: Data([1, 2, 3]))
        let url = uniqueTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try state.save(to: url)
        let raw = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: raw)
        #expect(object is [String: Any])
    }

    private func uniqueTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateTests-\(UUID().uuidString).json")
    }
}
