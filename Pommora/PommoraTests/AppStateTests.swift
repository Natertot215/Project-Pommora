//
//  AppStateTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

struct AppStateTests {
    @Test func defaultInitializerSetsSchemaVersion1() {
        let state = AppState()
        #expect(state.schemaVersion == 1)
        #expect(state.lastNexusBookmark == nil)
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
