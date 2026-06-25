//
//  PageStamperTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

@Suite
struct PageStamperTests {

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pommora-stamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("Stamps a frontmatter-less Page with a real ULID, preserving the body")
    func stampsUnstamped() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Note.md")
        try "# Heading\n\njust a body".write(to: url, atomically: true, encoding: .utf8)

        #expect(PageStamper.stampIfNeeded(at: url, nexusRoot: root))

        let reloaded = try PageFile.loadLenient(from: url, nexusRoot: root)
        #expect(!reloaded.frontmatter.id.hasPrefix("adopted-"))  // now a real ULID
        #expect(reloaded.body.contains("just a body"))  // body preserved
    }

    @Test("Leaves an already-stamped Page untouched (idempotent)")
    func idempotentOnStamped() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Note.md")
        let id = ULID.generate()
        let fm = PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date())
        try PageFile(frontmatter: fm, body: "x", title: "Note").save(to: url)

        #expect(!PageStamper.stampIfNeeded(at: url, nexusRoot: root))  // already real → no write

        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.frontmatter.id == id)  // unchanged
    }

    @Test("Preserves foreign frontmatter while stamping")
    func preservesForeignFrontmatter() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Note.md")
        try "---\naliases:\n  - foo\ncssclass: wide\n---\n\nbody"
            .write(to: url, atomically: true, encoding: .utf8)

        #expect(PageStamper.stampIfNeeded(at: url, nexusRoot: root))

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("aliases"))  // foreign keys survive
        #expect(raw.contains("cssclass"))
        #expect(raw.contains("id:"))  // real id introduced
    }

    @Test("Index-build stamp path persists a real ULID; the adopted- placeholder never lands on disk")
    func stampInPlacePersistsULID() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Note.md")
        try "# Heading\n\nbody".write(to: url, atomically: true, encoding: .utf8)

        let loaded = try PageFile.loadLenient(from: url, nexusRoot: root)
        #expect(loaded.frontmatter.id.hasPrefix("adopted-"))  // deterministic placeholder pre-stamp

        let stamped = PageStamper.stampInPlace(loaded, at: url)  // the path the index build uses
        #expect(!stamped.frontmatter.id.hasPrefix("adopted-"))  // returned id is a real ULID

        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.frontmatter.id == stamped.frontmatter.id)  // and it persisted
        #expect(!reloaded.frontmatter.id.hasPrefix("adopted-"))  // never an adopted- id on disk
    }

    @Test("A failed write keeps the deterministic adopted- id, stable across reloads")
    func failedWriteKeepsDeterministicID() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Note.md")
        try "# Heading\n\nbody".write(to: url, atomically: true, encoding: .utf8)

        let first = try PageFile.loadLenient(from: url, nexusRoot: root)
        let second = try PageFile.loadLenient(from: url, nexusRoot: root)
        #expect(first.frontmatter.id.hasPrefix("adopted-"))
        #expect(first.frontmatter.id == second.frontmatter.id)  // deterministic across reloads

        // A regular file where a directory is expected makes any save beneath it throw.
        let blocker = root.appendingPathComponent("blocker")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let unwritable = blocker.appendingPathComponent("Note.md")

        let result = PageStamper.stampInPlace(first, at: unwritable)
        #expect(result.frontmatter.id == first.frontmatter.id)  // failed write → original id kept
        #expect(result.frontmatter.id.hasPrefix("adopted-"))
    }
}
