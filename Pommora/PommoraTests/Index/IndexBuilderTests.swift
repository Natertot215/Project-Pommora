import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("IndexBuilderTests")
@MainActor
struct IndexBuilderTests {

    // MARK: - Fixture setup

    /// Builds a small nexus with 1 PageCollection "Notes" + 1 PageSet "Inbox"
    /// + 2 Pages, and 1 LEGACY item-side folder "Tasks" (raw `_itemtype.json`
    /// sidecar + 2 member `.md` files, written byte-for-byte — the Item types
    /// are deleted). The legacy folder exists to prove `populate` IGNORES
    /// on-disk item entities (PagesV2 — items are no longer indexed; the item
    /// tables were dropped from the schema at P7 / index v11).
    private func setup() async throws -> (Nexus, PommoraIndex) {
        let nexus = try TempNexus.make()

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!

        try await collectionManager.createPageCollection(name: "Inbox", inPageCollection: pt)
        let coll = collectionManager.pageCollections(in: pt).first!

        // Write 2 Pages directly to disk (mirrors existing test patterns).
        let page1URL = NexusPaths.pageFileURL(forTitle: "Page A", in: coll.folderURL)
        let page2URL = NexusPaths.pageFileURL(forTitle: "Page B", in: coll.folderURL)
        let now = Date()
        let fm1 = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let fm2 = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        try AtomicYAMLMarkdown.write(frontmatter: fm1, body: "", to: page1URL)
        try AtomicYAMLMarkdown.write(frontmatter: fm2, body: "", to: page2URL)

        // Lay down a legacy item-side folder by hand: an `_itemtype.json`
        // sidecar + 2 member `.md` files. No `_pagetype.json` → populate must
        // skip the whole folder.
        let itFolder = nexus.rootURL.appendingPathComponent("Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: itFolder, withIntermediateDirectories: true)
        let itemTypeJSON = """
            {"id":"\(ULID.generate())","modified_at":"2026-06-01T00:00:00Z","properties":[],"views":[]}
            """
        try Data(itemTypeJSON.utf8).write(to: itFolder.appendingPathComponent("_itemtype.json"))
        for title in ["Item One", "Item Two"] {
            let md = """
                ---
                id: \(ULID.generate())
                Class: item
                tier1: []
                tier2: []
                tier3: []
                properties: {}
                created_at: 2026-06-01T00:00:00Z
                ---
                """
            try Data(md.utf8).write(to: itFolder.appendingPathComponent("\(title).md"))
        }

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        return (nexus, idx)
    }

    // MARK: - Tests

    @Test func populateFromEmptyNexusProducesEmptyTables() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)

        try await IndexBuilder.populate(index: idx, from: nexus)

        let pageTypeCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1
        }
        #expect(pageTypeCount == 0)

        let pageCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
        }
        #expect(pageCount == 0)
    }

    @Test func populateIndexesAllPageCollections() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1
        }
        #expect(count == 1)
    }

    @Test func populateIndexesPageSets() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_sets") ?? -1
        }
        #expect(count == 1)

        // Verify FK: depth-1 set has parent_collection_id pointing to the page_collection.
        let matched = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM page_sets ps
                    JOIN page_collections pc ON ps.parent_collection_id = pc.id
                    WHERE pc.title = 'Notes' AND ps.title = 'Inbox'
                    """) ?? 0
        }
        #expect(matched == 1)
    }

    @Test func populateIndexesPagesIntoCollection() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
        }
        #expect(count == 2)

        // All pages must be linked to the one PageCollection.
        let withCollectionCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE page_collection_id IS NOT NULL") ?? 0
        }
        #expect(withCollectionCount == 2)
    }

    @Test func populateIndexesFrontmatterlessAdoptedPage() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!
        try await collectionManager.createPageCollection(name: "Inbox", inPageCollection: pt)
        let coll = collectionManager.pageCollections(in: pt).first!

        // A plain Markdown file with NO Pommora frontmatter — the exact shape of a
        // mirror doc dropped into a Nexus folder via Finder. Strict PageFile.load
        // rejects it; the launch scan must use the lenient loader so it still indexes.
        let adoptedURL = NexusPaths.pageFileURL(forTitle: "Adopted Doc", in: coll.folderURL)
        try "Just a plain body, no frontmatter.\n".write(to: adoptedURL, atomically: true, encoding: .utf8)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // Indexed purely from the launch scan — never opened, never CRUD-written.
        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE title = 'Adopted Doc'") ?? -1
        }
        #expect(count == 1, "Frontmatter-less adopted Page was dropped by the launch scan (strict-loader regression)")

        // And the wiki-link title resolver finds it — the user-visible payoff.
        let resolved = IndexQuery(idx).resolveUniqueEntity("Adopted Doc")
        #expect(resolved != nil, "Adopted Page is in the index but the title resolver can't find it")
    }

    @Test func populateHonorsFolderExclusionForLooseFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!
        try await collectionManager.createPageCollection(name: "Inbox", inPageCollection: pt)
        let coll = collectionManager.pageCollections(in: pt).first!

        // One real page to keep + one loose meta file to exclude by path — mirrors
        // CLAUDE.md sitting beside real specs in a collection root.
        let keepURL = NexusPaths.pageFileURL(forTitle: "Keep Me", in: coll.folderURL)
        let dropURL = NexusPaths.pageFileURL(forTitle: "CLAUDE", in: coll.folderURL)
        try "kept\n".write(to: keepURL, atomically: true, encoding: .utf8)
        try "meta — exclude me\n".write(to: dropURL, atomically: true, encoding: .utf8)

        // Exclude the loose file by its nexus-relative path (excluded_folders accepts
        // a file path; FolderFilter.isExcluded matches it segment-wise).
        let rootPath = nexus.rootURL.standardizedFileURL.path
        let relDrop = String(dropURL.standardizedFileURL.path.dropFirst(rootPath.count + 1))
        let filter = FolderFilter(nexusRoot: nexus.rootURL, excludedFolders: [relDrop])

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus, filter: filter)

        let keepCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE title = 'Keep Me'") ?? -1
        }
        #expect(keepCount == 1, "Non-excluded page must still index")

        let dropCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE title = 'CLAUDE'") ?? -1
        }
        #expect(dropCount == 0, "Excluded loose file leaked into the index — file-level folder-exclusion not honored")
    }

    @Test func populateIgnoresOnDiskItems() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)

        // PagesV2 P7 (schema v11): the item tables do not EXIST in a fresh
        // index — populating over a legacy on-disk item folder must not
        // resurrect them.
        let itemTableCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM sqlite_master
                    WHERE type = 'table' AND name IN ('items', 'item_types', 'item_collections')
                    """
            ) ?? -1
        }
        #expect(itemTableCount == 0, "Dropped item tables resurfaced in a fresh v11 index")

        // The legacy members must not leak into the pages table either —
        // a folder without `_pagetype.json` is skipped wholesale.
        let leakedPages = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM pages WHERE title IN ('Item One', 'Item Two')"
            ) ?? -1
        }
        #expect(leakedPages == 0, "legacy item member files leaked into the pages table")
    }

    @Test func populateTwiceIsIdempotent() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let pageTypeCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1
        }
        #expect(pageTypeCount == 1, "Duplicate page_collections rows after second populate")

        let pageCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
        }
        #expect(pageCount == 2, "Duplicate pages rows after second populate")
    }

    @Test func populateContextsAreasAndTopics() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let areaManager = AreaManager(nexus: nexus)
        await areaManager.loadAll()
        try await areaManager.create(name: "Work", icon: nil)
        try await areaManager.create(name: "Personal", icon: nil)

        let topicManager = TopicManager(nexus: nexus)
        await topicManager.loadAll()
        try await topicManager.create(name: "Finance", icon: nil)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let areaCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM contexts WHERE tier = 1") ?? -1
        }
        #expect(areaCount == 2)

        let topicCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM contexts WHERE tier = 2") ?? -1
        }
        #expect(topicCount == 1)
    }

    @Test func populateAgendaTasks() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let taskManager = AgendaTaskManager(nexus: nexus)
        await taskManager.loadAll()

        let now = Date()
        let task = AgendaTask(
            id: ULID.generate(), title: "Buy groceries", icon: nil,
            description: "",
            dueAt: nil, dueFloating: false, dueAllDay: false,
            startAt: nil,
            completed: false, completedAt: nil,
            priority: 0,
            recurrence: nil, alarmOffsets: [],
            calendarID: nil, eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: ["type": .select("Task")]
        )
        try await taskManager.createTask(task)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agenda_tasks") ?? -1
        }
        #expect(count == 1)
    }

    @Test func populateAgendaEvents() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let eventManager = AgendaEventManager(nexus: nexus)
        await eventManager.loadAll()

        let now = Date()
        let event = AgendaEvent(
            id: ULID.generate(), title: "Team standup", icon: nil,
            description: "",
            startAt: now, endAt: now.addingTimeInterval(1800),
            allDay: false,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            calendarID: nil, eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: now, modifiedAt: now,
            properties: ["type": .select("Event")]
        )
        try await eventManager.createEvent(event)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agenda_events") ?? -1
        }
        #expect(count == 1)
    }

    @Test func populateTierRelationsFromPageTierFields() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Create a area so we have a real tier-1 ID.
        let areaManager = AreaManager(nexus: nexus)
        await areaManager.loadAll()
        try await areaManager.create(name: "Work", icon: nil)
        let area = areaManager.areas.first!

        // Create a page type + collection + one page with tier1 populated.
        let collectionManager = PageCollectionManager(nexus: nexus)
        let setManager = PageSetManager(nexus: nexus)
        setManager.pageCollectionProvider = { [weak collectionManager] in collectionManager?.types ?? [] }
        collectionManager.pageSetManager = setManager
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!
        try await collectionManager.createPageCollection(name: "Inbox", inPageCollection: pt)
        let coll = collectionManager.pageCollections(in: pt).first!

        let now = Date()
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [area.id], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let pageURL = NexusPaths.pageFileURL(forTitle: "Linked Page", in: coll.folderURL)
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "", to: pageURL)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // The page's tier1 value emits one `context_links` row carrying the reserved
        // tier-1 property id and the area as target.
        let relCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM context_links WHERE source_kind = 'page' AND property_id = ?",
                arguments: [ReservedPropertyID.tier1]
            ) ?? -1
        }
        #expect(relCount == 1)

        let targetID = try await idx.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT target_id FROM context_links WHERE source_kind = 'page' AND property_id = ?",
                arguments: [ReservedPropertyID.tier1]
            )
        }
        #expect(targetID == area.id)
    }

    @Test func populatePropertyDefinitionsForPageCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let collectionManager = PageCollectionManager(nexus: nexus)
        await collectionManager.loadAll()
        try await collectionManager.createPageCollection(name: "Notes", icon: nil)
        let pt = collectionManager.types.first!

        // Add a property definition to the type. select requires at least one option.
        let def = PropertyDefinition(
            id: ULID.generate(), name: "Status", type: .select,
            selectOptions: [PropertyDefinition.SelectOption(value: "Open", label: "Open", color: .blue)]
        )
        try await collectionManager.addProperty(def, to: pt.id)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM property_definitions WHERE owning_type_kind = 'page_collection'"
            ) ?? -1
        }
        #expect(count == 1)

        let name = try await idx.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT name FROM property_definitions WHERE owning_type_kind = 'page_collection'"
            )
        }
        #expect(name == "Status")
    }
}
