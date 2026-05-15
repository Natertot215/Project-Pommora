//
//  NexusStoreTests.swift
//  PommoraTests
//

import Foundation
import Testing
@testable import Pommora

struct NexusStoreTests {
    @Test func applicationSupportDirReturnsValidURL() throws {
        let url = try NexusStore.applicationSupportDir()
        #expect(url.path.contains("Application Support"))
    }

    @Test func pommoraAppDirIsBundleIDNamespaced() throws {
        let url = try NexusStore.pommoraAppDir()
        guard let bundleID = Bundle.main.bundleIdentifier else {
            Issue.record("Test bundle has no identifier")
            return
        }
        #expect(url.lastPathComponent == bundleID)
    }

    @Test func appStateURLEndsWithStateJSON() throws {
        let url = try NexusStore.appStateURL()
        #expect(url.lastPathComponent == "state.json")
    }

    @Test func nexusDataDirUsesNexusIDSubdirectory() throws {
        let id = ULID.generate()
        let url = try NexusStore.nexusDataDir(nexusID: id)
        #expect(url.lastPathComponent == id)
        // Cleanup so subsequent test runs start fresh
        try? FileManager.default.removeItem(at: url)
    }

    @Test func databaseURLEndsWithPommoraDB() throws {
        let id = ULID.generate()
        let url = try NexusStore.databaseURL(nexusID: id)
        #expect(url.lastPathComponent == "nexus.db")
        // Cleanup the dir created as a side effect of nexusDataDir
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func databaseURLPathIncludesNexusesSegment() throws {
        let id = ULID.generate()
        let url = try NexusStore.databaseURL(nexusID: id)
        #expect(url.pathComponents.contains("nexuses"))
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
