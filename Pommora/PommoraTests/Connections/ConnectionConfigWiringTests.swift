import Foundation
import GRDB
import MarkdownPM
import Testing

@testable import Pommora

/// Proves `MarkdownEditorConfig.pommora` puts the LIVE `PommoraConnectionResolver`
/// instances into the right `services` slots — `.page` → `services.wikiLinks`
/// (`[[ ]]`), `.item` → `services.chipLinks` (`{{ }}`). This is the plumbing the
/// in-app editor relies on; no styler/probe needed.
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

    private func insertItem(id: String, title: String, icon: String, index: PommoraIndex) throws {
        let ts = now()
        try index.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO item_types (id, title, modified_at) VALUES (?, ?, ?)",
                arguments: ["it-test", "TestType", ts])
            try db.execute(
                sql: "INSERT INTO items (id, item_type_id, title, icon, modified_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [id, "it-test", title, icon, ts])
        }
    }

    @Test func pommoraConfigWiresLiveResolversIntoServices() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        try insertPage(id: ULID.generate(), title: "Alpha", index: index)
        try insertItem(id: ULID.generate(), title: "Beta", icon: "star.fill", index: index)

        let cfg = MarkdownEditorConfig.pommora(
            verticalInset: 0,
            pageResolver: PommoraConnectionResolver(index: index, kind: .page),
            itemResolver: PommoraConnectionResolver(index: index, kind: .item)
        )

        // `services.wikiLinks` is the live page resolver: a seeded page resolves,
        // a missing title is nil.
        #expect(
            cfg.services.wikiLinks.resolve(displayName: "Alpha", range: NSRange(location: 0, length: 5))?.exists
                == true)
        #expect(cfg.services.wikiLinks.resolve(displayName: "Ghost", range: NSRange(location: 0, length: 5)) == nil)

        // `services.chipLinks` is the live item resolver: a seeded item resolves.
        #expect(
            cfg.services.chipLinks.resolve(displayName: "Beta", range: NSRange(location: 0, length: 4))?.exists
                == true)
    }
}
