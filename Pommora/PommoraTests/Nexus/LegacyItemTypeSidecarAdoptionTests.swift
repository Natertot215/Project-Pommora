//
//  LegacyItemTypeSidecarAdoptionTests.swift
//  PommoraTests
//
//  PagesV2 P8 — the owed P3b pin (flagged in the plan's P10 section): what
//  adoption/auto-tag NOW does with a folder carrying a legacy `_itemtype.json`
//  sidecar left over from the retired item side.
//
//  Live behavior (read from `NexusAdopter`, 2026-06-10): `_itemtype.json` is
//  NOT among `recognizedSidecarsAt`'s kinds, so the folder is treated as
//  SIDECAR-LESS:
//    - `scan` classifies it as a fresh Page Type (`freshSidecars`), which is
//      deliberately excluded from `hasAnythingToAdopt` — NO consent gate.
//    - `autoTagMissingSidecars` silently writes `_pagetype.json` alongside.
//    - The stale `_itemtype.json` is left INERT on disk (`cleanupLegacyOrphans`
//      deletes only `_collection.json` / `_schema.json` / `_collection.json`).
//    - The folder's `.md` members index as PAGES (parent-sidecar authority;
//      the legacy `Class: item` stamp is non-authoritative).
//

import Foundation
import GRDB
import Testing

@testable import Pommora

@MainActor
@Suite("LegacyItemTypeSidecarAdoptionTests")
struct LegacyItemTypeSidecarAdoptionTests {

    /// Lays down an authentic legacy item-side folder: a raw `_itemtype.json`
    /// sidecar plus one `Class: item` member `.md` (the post-Items-as-Markdown,
    /// pre-PagesV2 on-disk shape).
    private func makeLegacyItemTypeFolder(in root: URL, title: String) throws -> URL {
        let folder = root.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sidecarID = ULID.generate()
        try FixtureFiles.writeJSON(
            #"{"id":"\#(sidecarID)","modified_at":"2026-06-01T00:00:00Z","properties":[],"views":[]}"#,
            to: folder.appendingPathComponent("_itemtype.json")
        )
        let memberID = ULID.generate()
        try FixtureFiles.write(
            """
            ---
            id: \(memberID)
            Class: item
            tier1: []
            tier2: []
            tier3: []
            properties: {}
            created_at: 2026-06-01T00:00:00Z
            ---
            """,
            to: folder.appendingPathComponent("Buy milk.md")
        )
        return folder
    }

    @Test("scan treats a legacy _itemtype.json folder as sidecar-less — fresh Page Type, no consent gate")
    func scanClassifiesLegacyItemTypeFolderAsFreshPageCollection() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makeLegacyItemTypeFolder(in: nexus.rootURL, title: "Errands")

        let plan = try NexusAdopter.scan(nexusRoot: nexus.rootURL)

        #expect(plan.freshSidecars.count == 1)
        #expect(plan.freshSidecars.first?.kind == .pageCollection)
        #expect(plan.inPlaceRenames.isEmpty)
        #expect(plan.unwrapSteps.isEmpty)
        // Fresh sidecars never trip the consent gate — no adoption preview.
        #expect(!plan.hasAnythingToAdopt)
    }

    @Test("auto-tag writes _pagetype.json and leaves the stale _itemtype.json inert on disk")
    func autoTagAddsPageCollectionAndLeavesItemTypeInert() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let folder = try makeLegacyItemTypeFolder(in: nexus.rootURL, title: "Errands")

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)

        let pageTypeSidecar = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
        let staleItemSidecar = folder.appendingPathComponent("_itemtype.json")
        #expect(FileManager.default.fileExists(atPath: pageTypeSidecar.path))
        // `_itemtype.json` is not a recognized legacy orphan — it stays, inert.
        #expect(FileManager.default.fileExists(atPath: staleItemSidecar.path))
    }

    @Test(".md members of the auto-tagged folder index as pages")
    func legacyMembersIndexAsPages() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        try makeLegacyItemTypeFolder(in: nexus.rootURL, title: "Errands")

        NexusAdopter.autoTagMissingSidecars(at: nexus.rootURL)
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let pageCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM pages WHERE title = 'Buy milk'") ?? -1
        }
        #expect(pageCount == 1, "the legacy `Class: item` member must index as a page")
    }
}
