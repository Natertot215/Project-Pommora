import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("ConnectionRebuildTests")
@MainActor
struct ConnectionRebuildTests {

    /// Cold-start `insertConnections` pass: a page whose body contains `[[Other]]`
    /// must emit a resolved `connections` row after `IndexBuilder.populate`.
    @Test func populateBackfillsConnectionFromPageBody() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Seed a PageType "Notes" so the vault is discovered during the filesystem walk.
        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)

        // Vault folder for writing page files directly (mirrors RebuildResilienceTests fixture pattern).
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)

        let now = Date()

        // "Other" page — target of the wikilink.
        let otherID = ULID.generate()
        let otherFM = PageFrontmatter(
            id: otherID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: otherFM, body: "",
            to: NexusPaths.pageFileURL(forTitle: "Other", in: vaultFolder))

        // "Source" page — body contains [[Other]], which should resolve to otherID.
        let sourceID = ULID.generate()
        let sourceFM = PageFrontmatter(
            id: sourceID, icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        try AtomicYAMLMarkdown.write(
            frontmatter: sourceFM, body: "[[Other]]",
            to: NexusPaths.pageFileURL(forTitle: "Source", in: vaultFolder))

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // Assert one connections row: source = Source, target = Other, resolved = 1.
        let row = try await idx.dbQueue.read { db -> Row? in
            try Row.fetchOne(
                db,
                sql: "SELECT source_id, target_id, target_title, resolved FROM connections WHERE source_id = ?",
                arguments: [sourceID])
        }

        #expect(row != nil, "Expected a connections row for the Source page")
        if let row {
            #expect(row["target_title"] as String? == "other")
            #expect(row["target_id"] as String? == otherID)
            #expect(row["resolved"] as Int? == 1)
        }
    }
}
