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

    private func tempPage(_ markdown: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pom-modat-\(UUID().uuidString).md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("loadLenient honors a Page's explicit modified_at")
    func pageLoadLenientHonorsModifiedAt() throws {
        let url = try tempPage(
            """
            ---
            id: 01PAGE
            created_at: 2020-01-01T00:00:00Z
            modified_at: 2021-06-15T10:00:00Z
            ---

            body
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        let pf = try PageFile.loadLenient(from: url, nexusRoot: url.deletingLastPathComponent())
        #expect(pf.frontmatter.modifiedAt == ISO8601DateFormatter().date(from: "2021-06-15T10:00:00Z"))
    }

    @Test("loadLenient keeps a Page's stamp even when file mtime is newer (external edits don't count)")
    func pageLoadLenientStampBeatsNewerMtime() throws {
        let url = try tempPage(
            """
            ---
            id: 01PAGE
            created_at: 2020-01-01T00:00:00Z
            modified_at: 2021-06-15T10:00:00Z
            ---

            body
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        // Touch the file into the future — the stored stamp must still win
        // (stored-wins, never max(stored, mtime)), so an external edit never
        // moves Last-Edited.
        let future = Date(timeIntervalSince1970: 4_070_908_800)  // 2099-01-01
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: url.path)

        let pf = try PageFile.loadLenient(from: url, nexusRoot: url.deletingLastPathComponent())
        #expect(pf.frontmatter.modifiedAt == ISO8601DateFormatter().date(from: "2021-06-15T10:00:00Z"))
    }

    @Test("loadLenient falls back to file mtime when a Page lacks modified_at")
    func pageLoadLenientFallsBackToMtime() throws {
        let url = try tempPage(
            """
            ---
            id: 01PAGE
            created_at: 2020-01-01T00:00:00Z
            ---

            body
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        let mtime = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let pf = try PageFile.loadLenient(from: url, nexusRoot: url.deletingLastPathComponent())
        let modified = try #require(pf.frontmatter.modifiedAt)
        #expect(abs(modified.timeIntervalSince(mtime)) < 2)  // fell back to file mtime
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
