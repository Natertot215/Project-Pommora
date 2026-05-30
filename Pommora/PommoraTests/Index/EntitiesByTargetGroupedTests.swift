//
//  EntitiesByTargetGroupedTests.swift
//  PommoraTests
//
//  Task 4a — `IndexQuery.entitiesByTargetGrouped`: the grouped data feed for the
//  relation value picker. `.pageType` / `.itemType` scopes produce Collection/Set
//  groups + loose (no-collection) leaves; every other scope returns flat (empty
//  groups, everything in `rootEntities`) so the picker renders a flat list.
//
//  Seeds the index directly via `IndexUpdater` (FK-correct order: parent type →
//  collection → pages). Struct name MATCHES the filename (quirk #18).
//

import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("EntitiesByTargetGroupedTests")
struct EntitiesByTargetGroupedTests {

    @Test func pageTypeScopeGroupsCollectionsAndLooseLeaves() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        // page_type → one Collection (2 member pages, icons set) + one loose page.
        let typeID = ULID.generate()
        try updater.upsertPageType(
            PageType(id: typeID, title: "Notes", icon: nil, properties: [], views: [], modifiedAt: Date())
        )
        let collID = ULID.generate()
        let collFolder = NexusPaths.vaultFolderURL(forTitle: "Notes", in: nexus)
            .appendingPathComponent("Daily", isDirectory: true)
        try updater.upsertPageCollection(
            PageCollection(id: collID, typeID: typeID, title: "Daily", folderURL: collFolder, modifiedAt: Date())
        )

        func seedPage(_ title: String, icon: String?, collection: String?) throws {
            let id = ULID.generate()
            let fm = PageFrontmatter(
                id: id, icon: icon, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date()
            )
            let url = nexus.rootURL.appendingPathComponent("\(title).md")
            try updater.upsertPage(
                PageMeta(id: id, title: title, url: url, frontmatter: fm),
                pageTypeID: typeID, pageCollectionID: collection
            )
        }
        try seedPage("Member A", icon: "doc.text", collection: collID)
        try seedPage("Member B", icon: "star", collection: collID)
        try seedPage("Loose One", icon: "tray", collection: nil)

        let grouped = try await IndexQuery(index).entitiesByTargetGrouped(.pageType(typeID))

        #expect(grouped.groups.count == 1)
        let group = try #require(grouped.groups.first)
        #expect(group.container.id == collID)
        #expect(group.container.title == "Daily")
        #expect(group.container.kind == .pageCollection)
        #expect(group.members.count == 2)
        #expect(group.members.allSatisfy { $0.icon != nil })
        #expect(grouped.rootEntities.count == 1)
        #expect(grouped.rootEntities.first?.title == "Loose One")
    }

    @Test func contextTierScopeReturnsFlatNoGroups() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        let updater = IndexUpdater(index)

        let spaceID = ULID.generate()
        try updater.upsertContext(
            Space(id: spaceID, title: "Personal", color: nil, icon: "person", blocks: [], modifiedAt: Date())
        )

        let grouped = try await IndexQuery(index).entitiesByTargetGrouped(.contextTier(1))

        // Non-pageType/itemType scope → flat: no groups; the Space lands in rootEntities.
        #expect(grouped.groups.isEmpty)
        #expect(grouped.rootEntities.contains { $0.id == spaceID })
    }
}
