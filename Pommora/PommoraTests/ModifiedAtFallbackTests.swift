//
//  ModifiedAtFallbackTests.swift
//  PommoraTests
//
//  `modified_at` is kept (still written) but NOT a hard decode requirement: a sidecar
//  lacking it — e.g. one written by the React build — falls back to the file's mtime via
//  AtomicJSON, rather than failing to decode (which dropped the entity from the sidebar).
//

import Foundation
import Testing

@testable import Pommora

@Suite
struct ModifiedAtFallbackTests {

    private func tempFile(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pom-modat-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("PageCollection decodes a sidecar lacking modified_at (falls back to file mtime)")
    func collectionWithoutModifiedAt() throws {
        let url = try tempFile(#"{"id":"01ABCDEF","schema_version":0}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let mtime = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!

        let c = try AtomicJSON.decode(PageCollection.self, from: url)  // must NOT throw
        #expect(c.id == "01ABCDEF")
        #expect(abs(c.modifiedAt.timeIntervalSince(mtime)) < 2)  // fell back to the file mtime
    }

    @Test("PageSet decodes a sidecar lacking modified_at")
    func setWithoutModifiedAt() throws {
        let url = try tempFile(#"{"id":"01SET","parent_id":"01COL"}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let s = try AtomicJSON.decode(PageSet.self, from: url)  // must NOT throw
        #expect(s.id == "01SET")
    }

    @Test("An explicit modified_at is still honored when present")
    func collectionWithExplicitModifiedAt() throws {
        let url = try tempFile(#"{"id":"x","modified_at":"2026-05-24T22:00:44Z"}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let c = try AtomicJSON.decode(PageCollection.self, from: url)
        #expect(c.modifiedAt == ISO8601DateFormatter().date(from: "2026-05-24T22:00:44Z"))
    }
}
