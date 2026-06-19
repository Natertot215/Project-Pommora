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
}
