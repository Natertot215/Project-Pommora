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
    /// `PageCollectionManager.deleteProperty`'s inline loop. The same frontmatter-less
    /// `.md` must be tolerated.
    @Test func plainPropertyDeleteToleratesFrontmatterlessMemberPage() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageCollection(name: "Notes", icon: nil)
        let notes = manager.types.first { $0.title == "Notes" }!

        let def = PropertyDefinition(id: "", name: "Count", type: .number)
        try await manager.addProperty(def, to: notes.id)
        let propID = manager.types.first { $0.title == "Notes" }!
            .properties.first { $0.type == .number }!.id

        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "Notes", in: nexus)
        let plainURL = collectionFolder.appendingPathComponent("Plain Note.md")
        try "Plain markdown, no frontmatter.\n"
            .write(to: plainURL, atomically: true, encoding: .utf8)

        try await manager.deleteProperty(id: propID, in: notes.id)

        #expect(
            manager.types.first { $0.title == "Notes" }!
                .properties.contains { $0.id == propID } == false)
        #expect(FileManager.default.fileExists(atPath: plainURL.path))
    }

}
