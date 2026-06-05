//
//  MemberFileStripResilienceTests.swift
//  PommoraTests
//
//  Task 8 / Bug A — the member-file value-strip (property delete, change-type)
//  must TOLERATE a member file it can't decode. Pre-fix every strip site did a
//  hard `try load(...)` / `decode(...)` per member; a hand-authored
//  frontmatter-less `.md` decodes to `{}`, and `PageFrontmatter.init(from:)`
//  requires `id`, so it throws `DecodingError.keyNotFound(.id)` — surfaced as
//  the "The data couldn't be read because it is missing." toast and aborted the
//  whole schema mutation. The fix routes every strip site through
//  `MemberFileStrip.forEach`, which skips + logs an unreadable member: a file we
//  can't read can't be carrying the property value, so skipping is lossless (the
//  canonical schema-sidecar strip is staged separately).
//
//  Struct name MATCHES the filename (quirk #18 — Swift Testing filters by
//  suite/type name, not source filename).
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("MemberFileStripResilienceTests")
struct MemberFileStripResilienceTests {

    /// The non-paired path: deleting a plain property also strips member files via
    /// `PageTypeManager.deleteProperty`'s inline loop. The same frontmatter-less
    /// `.md` must be tolerated.
    @Test func plainPropertyDeleteToleratesFrontmatterlessMemberPage() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageType(name: "Notes", icon: nil)
        let notes = manager.types.first { $0.title == "Notes" }!

        let def = PropertyDefinition(id: "", name: "Count", type: .number)
        try await manager.addProperty(def, to: notes.id)
        let propID = manager.types.first { $0.title == "Notes" }!
            .properties.first { $0.type == .number }!.id

        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
        let plainURL = vaultFolder.appendingPathComponent("Plain Note.md")
        try "Plain markdown, no frontmatter.\n"
            .write(to: plainURL, atomically: true, encoding: .utf8)

        try await manager.deleteProperty(id: propID, in: notes.id)

        #expect(
            manager.types.first { $0.title == "Notes" }!
                .properties.contains { $0.id == propID } == false)
        #expect(FileManager.default.fileExists(atPath: plainURL.path))
    }

    /// The Item side (defensive symmetry with the `.md` path): deleting a property
    /// strips member `.json` items via `ItemTypeManager.deleteProperty`'s inline
    /// loop. A corrupt `.json` that can't decode as `Item` must be tolerated.
    @Test func itemPropertyDeleteToleratesUndecodableMemberJSON() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = ItemTypeManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createItemType(name: "Books", icon: nil)
        let books = manager.types.first { $0.title == "Books" }!

        let def = PropertyDefinition(id: "", name: "Pages", type: .number)
        try await manager.addProperty(def, to: books.id)
        let propID = manager.types.first { $0.title == "Books" }!
            .properties.first { $0.type == .number }!.id

        // A non-underscore `.json` in the Item Type folder that is NOT a valid Item
        // (missing required fields) — the strip loop's `decode(Item.self)` throws.
        let typeFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Books")
        let badURL = typeFolder.appendingPathComponent("Corrupt.json")
        try "{ \"not_an_item\": true }".write(to: badURL, atomically: true, encoding: .utf8)

        try await manager.deleteProperty(id: propID, in: books.id)

        #expect(
            manager.types.first { $0.title == "Books" }!
                .properties.contains { $0.id == propID } == false)
        #expect(FileManager.default.fileExists(atPath: badURL.path))
    }
}
