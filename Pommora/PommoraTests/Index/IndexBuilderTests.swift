import Foundation
import GRDB
import Testing

@testable import Pommora

@Suite("IndexBuilderTests")
@MainActor
struct IndexBuilderTests {

    // MARK: - Fixture setup

    /// Builds a small nexus with 1 PageType "Notes" + 1 PageCollection "Inbox"
    /// + 2 Pages, and 1 ItemType "Tasks" + 2 Items. The item side exists to
    /// prove `populate` IGNORES on-disk item entities (PagesV2 — items are no
    /// longer indexed; their tables survive empty until the P7 schema bump).
    private func setup() async throws -> (Nexus, PommoraIndex) {
        let nexus = try TempNexus.make()

        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!

        try await pageTypeManager.createPageCollection(name: "Inbox", inPageType: pt)
        let coll = pageTypeManager.pageCollections(in: pt).first!

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

        let itemTypeManager = ItemTypeManager(nexus: nexus)
        await itemTypeManager.loadAll()
        try await itemTypeManager.createItemType(name: "Tasks", icon: nil)
        let it = itemTypeManager.types.first!
        let itFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Tasks")

        // Write 2 Items directly to disk.
        let item1 = Item(
            id: ULID.generate(), title: "Item One", icon: nil,
            description: "", tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let item2 = Item(
            id: ULID.generate(), title: "Item Two", icon: nil,
            description: "", tier1: [], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let item1URL = NexusPaths.itemFileURL(forTitle: "Item One", in: itFolder)
        let item2URL = NexusPaths.itemFileURL(forTitle: "Item Two", in: itFolder)
        try item1.save(to: item1URL)
        try item2.save(to: item2URL)
        _ = it  // suppress unused-variable warning

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
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types") ?? -1
        }
        #expect(pageTypeCount == 0)

        let itemTypeCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_types") ?? -1
        }
        #expect(itemTypeCount == 0)

        let pageCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
        }
        #expect(pageCount == 0)
    }

    @Test func populateIndexesAllPageTypes() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types") ?? -1
        }
        #expect(count == 1)
    }

    @Test func populateIndexesPageCollections() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_collections") ?? -1
        }
        #expect(count == 1)

        // Verify FK: page_collection.page_type_id matches the page_type row.
        let matched = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM page_collections pc
                    JOIN page_types pt ON pc.page_type_id = pt.id
                    WHERE pt.title = 'Notes' AND pc.title = 'Inbox'
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

        // All pages must be linked to the one PageType.
        let withTypeCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages WHERE page_type_id IS NOT NULL") ?? 0
        }
        #expect(withTypeCount == 2)
    }

    @Test func populateIndexesFrontmatterlessAdoptedPage() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!
        try await pageTypeManager.createPageCollection(name: "Inbox", inPageType: pt)
        let coll = pageTypeManager.pageCollections(in: pt).first!

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
        let resolved = IndexQuery(idx).resolveUniqueEntity("Adopted Doc", kind: .page)
        #expect(resolved != nil, "Adopted Page is in the index but the title resolver can't find it")
    }

    @Test func populateHonorsFolderExclusionForLooseFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!
        try await pageTypeManager.createPageCollection(name: "Inbox", inPageType: pt)
        let coll = pageTypeManager.pageCollections(in: pt).first!

        // One real page to keep + one loose meta file to exclude by path — mirrors
        // CLAUDE.md sitting beside real specs in a vault root.
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

        // The fixture wrote 1 ItemType + 2 Items to disk; populate must index
        // NONE of them (PagesV2 — the item tables stay empty until P7 drops them).
        let itemTypeCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_types") ?? -1
        }
        #expect(itemTypeCount == 0, "IndexBuilder re-indexed an on-disk ItemType")

        let itemCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items") ?? -1
        }
        #expect(itemCount == 0, "IndexBuilder re-indexed on-disk Items")
    }

    @Test func populateTwiceIsIdempotent() async throws {
        let (nexus, idx) = try await setup()
        defer { TempNexus.cleanup(nexus) }

        try await IndexBuilder.populate(index: idx, from: nexus)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let pageTypeCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM page_types") ?? -1
        }
        #expect(pageTypeCount == 1, "Duplicate page_types rows after second populate")

        let pageCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pages") ?? -1
        }
        #expect(pageCount == 2, "Duplicate pages rows after second populate")
    }

    @Test func populateContextsSpacesAndTopics() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let spaceManager = SpaceManager(nexus: nexus)
        await spaceManager.loadAll()
        try await spaceManager.create(name: "Work", color: nil, icon: nil)
        try await spaceManager.create(name: "Personal", color: nil, icon: nil)

        let topicManager = TopicManager(
            nexus: nexus,
            contextProvider: {
                NexusContext(
                    lookupSpace: { _ in nil },
                    lookupTopic: { _ in nil },
                    lookupProject: { _ in nil },
                    lookupVault: { _ in nil }
                )
            }
        )
        await topicManager.loadAll()
        try await topicManager.createTopic(name: "Finance", parents: [], icon: nil)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let spaceCount = try await idx.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM contexts WHERE tier = 1") ?? -1
        }
        #expect(spaceCount == 2)

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

        // Create a space so we have a real tier-1 ID.
        let spaceManager = SpaceManager(nexus: nexus)
        await spaceManager.loadAll()
        try await spaceManager.create(name: "Work", color: nil, icon: nil)
        let space = spaceManager.spaces.first!

        // Create a page type + collection + one page with tier1 populated.
        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!
        try await pageTypeManager.createPageCollection(name: "Inbox", inPageType: pt)
        let coll = pageTypeManager.pageCollections(in: pt).first!

        let now = Date()
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [space.id], tier2: [], tier3: [],
            properties: [:],
            createdAt: now, modifiedAt: now
        )
        let pageURL = NexusPaths.pageFileURL(forTitle: "Linked Page", in: coll.folderURL)
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "", to: pageURL)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        // The page's tier1 value emits one `context_links` row carrying the reserved
        // tier-1 property id and the space as target.
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
        #expect(targetID == space.id)
    }

    @Test func populatePropertyDefinitionsForPageType() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pageTypeManager = PageTypeManager(nexus: nexus)
        await pageTypeManager.loadAll()
        try await pageTypeManager.createPageType(name: "Notes", icon: nil)
        let pt = pageTypeManager.types.first!

        // Add a property definition to the type. select requires at least one option.
        let def = PropertyDefinition(
            id: ULID.generate(), name: "Status", type: .select,
            selectOptions: [PropertyDefinition.SelectOption(value: "Open", label: "Open", color: .blue)]
        )
        try await pageTypeManager.addProperty(def, to: pt.id)

        let (idx, _) = try PommoraIndex.open(at: nexus.rootURL)
        try await IndexBuilder.populate(index: idx, from: nexus)

        let count = try await idx.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM property_definitions WHERE owning_type_kind = 'page_type'"
            ) ?? -1
        }
        #expect(count == 1)

        let name = try await idx.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT name FROM property_definitions WHERE owning_type_kind = 'page_type'"
            )
        }
        #expect(name == "Status")
    }
}
