//
//  FolderIndexSyncTests.swift
//  PommoraTests
//
//  F.1.k regression coverage for quirk #15: loadAll must sync in-memory
//  Folders to the SQLite index. Mirrors `LoadAllIndexSyncTests` for the
//  third tier — a Folder sidecar that landed via Finder or auto-tagging
//  must be upserted into SQLite by PageTypeManager.loadAll so subsequent
//  Folder-scoped page CRUD finds the FK target.
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("Folder index sync on loadAll")
struct FolderIndexSyncTests {

    /// Simulates Finder-built (or auto-tagged) state: a Folder sidecar lives
    /// on disk but was never created via `createFolder` so `upsertFolder`
    /// never ran. loadAll should defensively upsert the Folder so subsequent
    /// page CRUD into that Folder doesn't FK-fail.
    @Test func loadAllSyncsFolderToIndex() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)

        // Build on-disk state directly (no CRUD): Type + Collection + Folder.
        let pageTypeID = ULID.generate()
        let collectionID = ULID.generate()
        let folderID = ULID.generate()
        let now = Date()

        let typeFolder = nexus.rootURL.appendingPathComponent("Research", isDirectory: true)
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        try PageType(
            id: pageTypeID, title: "Research", icon: nil,
            properties: [], views: [], modifiedAt: now
        ).save(to: typeFolder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename))

        let collFolder = typeFolder.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        try PageCollection(
            id: collectionID, typeID: pageTypeID, title: "Sources",
            folderURL: collFolder, modifiedAt: now
        ).save(to: collFolder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename))

        let folderFolder = collFolder.appendingPathComponent("Topic A", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderFolder, withIntermediateDirectories: true
        )
        try Folder(
            id: folderID, typeID: pageTypeID, collectionID: collectionID,
            title: "Topic A", folderURL: folderFolder, modifiedAt: now
        ).save(to: folderFolder.appendingPathComponent(NexusPaths.folderSidecarFilename))

        // DB starts empty for the folders table.
        let initialCount = try await index.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folders") ?? -1
        }
        #expect(initialCount == 0)

        // Wire IndexUpdater + load.
        let manager = PageTypeManager(nexus: nexus)
        manager.indexUpdater = IndexUpdater(index)
        await manager.loadAll()

        // Post-loadAll: folders row exists with FKs to type + collection.
        let postCount = try await index.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM folders WHERE id = ?",
                arguments: [folderID]
            ) ?? -1
        }
        #expect(postCount == 1)

        // Subsequent upsertPage with this Folder's id MUST NOT FK-fail.
        let updater = IndexUpdater(index)
        let pageMeta = PageMeta(
            id: ULID.generate(),
            title: "Note",
            url: folderFolder.appendingPathComponent("Note.md"),
            frontmatter: PageFrontmatter(
                id: ULID.generate(), icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:], createdAt: now
            )
        )
        try updater.upsertPage(
            pageMeta,
            pageTypeID: pageTypeID,
            pageCollectionID: collectionID,
            pageFolderID: folderID
        )

        // Verify the page row landed with all three FK columns populated.
        let pageID = pageMeta.id
        let pageRow = try await index.dbQueue.read { db -> [String: String?] in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT page_type_id, page_collection_id, page_folder_id
                      FROM pages
                     WHERE id = ?
                """,
                arguments: [pageID]
            ).map {
                [
                    "type": $0["page_type_id"] as String?,
                    "collection": $0["page_collection_id"] as String?,
                    "folder": $0["page_folder_id"] as String?,
                ]
            } ?? [:]
        }
        #expect(pageRow["type"] == pageTypeID)
        #expect(pageRow["collection"] == collectionID)
        #expect(pageRow["folder"] == folderID)
    }
}
