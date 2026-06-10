import Foundation
import GRDB
import MarkdownPM
import Testing

@testable import Pommora

/// Proves `MarkdownEditorConfig.pommora` puts the LIVE `PommoraConnectionResolver`
/// into `services.wikiLinks` (`[[ ]]`). This is the plumbing the in-app editor
/// relies on; no styler/probe needed.
@Suite("ConnectionConfigWiringTests")
@MainActor
struct ConnectionConfigWiringTests {

    private func now() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.string(from: Date())
    }

    private func insertPage(id: String, title: String, index: PommoraIndex) throws {
        let ts = now()
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO page_types (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["pt-test", "TestVault", ts])
            try db.execute(
                sql: "INSERT INTO pages (id, page_type_id, title, modified_at) VALUES (?, ?, ?, ?)",
                arguments: [id, "pt-test", title, ts])
        }
    }

    @Test func pommoraConfigWiresLiveResolversIntoServices() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        try insertPage(id: ULID.generate(), title: "Alpha", index: index)

        let cfg = MarkdownEditorConfig.pommora(
            verticalInset: 0,
            pageResolver: PommoraConnectionResolver(index: index)
        )

        // `services.wikiLinks` is the live page resolver: a seeded page resolves,
        // a missing title is nil.
        #expect(
            cfg.services.wikiLinks.resolve(displayName: "Alpha", range: NSRange(location: 0, length: 5))?.exists
                == true)
        #expect(cfg.services.wikiLinks.resolve(displayName: "Ghost", range: NSRange(location: 0, length: 5)) == nil)
    }
}
