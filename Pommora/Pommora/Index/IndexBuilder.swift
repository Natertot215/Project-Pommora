import Foundation
import GRDB

// MARK: - Sendable snapshot types (pure data, passed across actor boundaries)

/// Snapshot of a PageType and its children, safe to pass into a @Sendable closure.
private struct PageTypeSnapshot: Sendable {
    let id: String
    let title: String
    let icon: String?
    let modifiedAt: Date
    let schemaVersion: Int
    let properties: [PropertyDefinition]
    let collections: [PageCollectionSnapshot]
    let directPages: [PageSnapshot]
}

private struct PageCollectionSnapshot: Sendable {
    let id: String
    let title: String
    let modifiedAt: Date
    let schemaVersion: Int
    let pages: [PageSnapshot]
}

private struct PageSnapshot: Sendable {
    let id: String
    let title: String
    let properties: [String: PropertyValue]
    let modifiedAt: Date
    let pageTypeID: String
    let collectionID: String?
    let tier1: [String]
    let tier2: [String]
    let tier3: [String]
}

private struct ItemTypeSnapshot: Sendable {
    let id: String
    let title: String
    let icon: String?
    let modifiedAt: Date
    let schemaVersion: Int
    let properties: [PropertyDefinition]
    let collections: [ItemCollectionSnapshot]
    let directItems: [ItemSnapshot]
}

private struct ItemCollectionSnapshot: Sendable {
    let id: String
    let title: String
    let modifiedAt: Date
    let schemaVersion: Int
    let items: [ItemSnapshot]
}

private struct ItemSnapshot: Sendable {
    let id: String
    let title: String
    let description: String?
    let properties: [String: PropertyValue]
    let modifiedAt: Date
    let itemTypeID: String
    let collectionID: String?
    let tier1: [String]
    let tier2: [String]
    let tier3: [String]
}

private struct AgendaTaskSnapshot: Sendable {
    let id: String
    let title: String
    let dueAt: Date?
    let properties: [String: PropertyValue]
    let modifiedAt: Date
    let tier1: [String]
    let tier2: [String]
    let tier3: [String]
}

private struct AgendaEventSnapshot: Sendable {
    let id: String
    let title: String
    let startAt: Date
    let endAt: Date
    let properties: [String: PropertyValue]
    let modifiedAt: Date
    let tier1: [String]
    let tier2: [String]
    let tier3: [String]
}

private struct ContextSnapshot: Sendable {
    let id: String
    let tier: Int
    let title: String
    let parentTopicID: String?
}

private struct TaskSchemaSnapshot: Sendable {
    let properties: [PropertyDefinition]
}

private struct EventSchemaSnapshot: Sendable {
    let properties: [PropertyDefinition]
}

private struct NexusSnapshot: Sendable {
    let pageTypes: [PageTypeSnapshot]
    let itemTypes: [ItemTypeSnapshot]
    let tasks: [AgendaTaskSnapshot]
    let taskSchema: TaskSchemaSnapshot?
    let events: [AgendaEventSnapshot]
    let eventSchema: EventSchemaSnapshot?
    let contexts: [ContextSnapshot]
}

// MARK: - IndexBuilder

/// Populates a fresh PommoraIndex from on-disk Nexus content. Used on first
/// launch + on schema_version mismatch (rebuild) + on explicit "rebuild index"
/// from Settings. Idempotent — runs inside a single transaction; failures
/// roll the DB back to pre-call state.
///
/// Idempotence strategy: DELETE all rows from each table before re-inserting.
/// Since the DB is a regeneratable index (no user data), a full wipe + repopulate
/// is safe and simpler than INSERT OR REPLACE across compound-key tables.
final class IndexBuilder {

    // MARK: - Public API

    /// Walks `nexus`'s on-disk content and populates `index`'s tables.
    /// Throws on filesystem read failure or DB write failure.
    static func populate(index: PommoraIndex, from nexus: Nexus) async throws {
        // Phase 1: Walk the filesystem on the @MainActor (domain types are @MainActor-isolated).
        let snapshot = buildSnapshot(from: nexus)

        // Phase 2: Write collected data into the DB inside a @Sendable closure.
        // No @MainActor calls happen inside here — all data is pre-collected in `snapshot`.
        try await index.dbQueue.write { db in
            try clearAllTables(db)
            try insertPageTypes(db, snapshot: snapshot)
            try insertItemTypes(db, snapshot: snapshot)
            try insertAgendaTasks(db, snapshot: snapshot)
            try insertAgendaEvents(db, snapshot: snapshot)
            try insertContexts(db, snapshot: snapshot)
            try insertRelations(db, snapshot: snapshot)
            try insertTierLinks(db, snapshot: snapshot)
        }
    }

    // MARK: - Phase 1: Filesystem walk (runs on @MainActor)

    private static func buildSnapshot(from nexus: Nexus) -> NexusSnapshot {
        NexusSnapshot(
            pageTypes: collectPageTypes(from: nexus),
            itemTypes: collectItemTypes(from: nexus),
            tasks: collectTasks(from: nexus),
            taskSchema: collectTaskSchema(from: nexus),
            events: collectEvents(from: nexus),
            eventSchema: collectEventSchema(from: nexus),
            contexts: collectContexts(from: nexus)
        )
    }

    private static func collectPageTypes(from nexus: Nexus) -> [PageTypeSnapshot] {
        let root = nexus.rootURL
        let topLevel = (try? Filesystem.childFolders(of: root)) ?? []
        var result: [PageTypeSnapshot] = []

        for folder in topLevel where !folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.hasPrefix("_") {
            let metaURL = folder.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            guard Filesystem.fileExists(at: metaURL),
                let pageType = try? PageType.load(from: metaURL)
            else { continue }

            // Collections
            let subFolders = (try? Filesystem.childFolders(of: folder)) ?? []
            var collections: [PageCollectionSnapshot] = []
            for sub in subFolders where !sub.lastPathComponent.hasPrefix("_") && !sub.lastPathComponent.hasPrefix(".") {
                let collURL = sub.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
                guard Filesystem.fileExists(at: collURL),
                    let coll = try? PageCollection.load(from: collURL)
                else { continue }
                let pages = collectPagesInFolder(sub, pageTypeID: pageType.id, collectionID: coll.id)
                collections.append(PageCollectionSnapshot(
                    id: coll.id,
                    title: coll.title,
                    modifiedAt: coll.modifiedAt,
                    schemaVersion: coll.schemaVersion,
                    pages: pages
                ))
            }

            let directPages = collectPagesInFolder(folder, pageTypeID: pageType.id, collectionID: nil)

            result.append(PageTypeSnapshot(
                id: pageType.id,
                title: pageType.title,
                icon: pageType.icon,
                modifiedAt: pageType.modifiedAt,
                schemaVersion: pageType.schemaVersion,
                properties: pageType.properties,
                collections: collections,
                directPages: directPages
            ))
        }
        return result
    }

    private static func collectPagesInFolder(
        _ folderURL: URL,
        pageTypeID: String,
        collectionID: String?
    ) -> [PageSnapshot] {
        let urls = (try? Filesystem.children(of: folderURL) { $0.pathExtension == "md" }) ?? []
        return urls.compactMap { url -> PageSnapshot? in
            guard let pf = try? PageFile.load(from: url) else { return nil }
            let fm = pf.frontmatter
            return PageSnapshot(
                id: fm.id,
                title: pf.title,
                properties: fm.properties,
                modifiedAt: fm.modifiedAt ?? fm.createdAt,
                pageTypeID: pageTypeID,
                collectionID: collectionID,
                tier1: fm.tier1,
                tier2: fm.tier2,
                tier3: fm.tier3
            )
        }
    }

    private static func collectItemTypes(from nexus: Nexus) -> [ItemTypeSnapshot] {
        let root = nexus.rootURL
        let topLevel = (try? Filesystem.childFolders(of: root)) ?? []
        var result: [ItemTypeSnapshot] = []

        for folder in topLevel where !folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.hasPrefix("_") {
            let metaURL = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
            guard Filesystem.fileExists(at: metaURL),
                let itemType = try? ItemType.load(from: metaURL)
            else { continue }

            let subFolders = (try? Filesystem.childFolders(of: folder)) ?? []
            var collections: [ItemCollectionSnapshot] = []
            for sub in subFolders where !sub.lastPathComponent.hasPrefix("_") && !sub.lastPathComponent.hasPrefix(".") {
                let collURL = sub.appendingPathComponent(NexusPaths.itemCollectionSidecarFilename)
                guard Filesystem.fileExists(at: collURL),
                    let coll = try? ItemCollection.load(from: collURL)
                else { continue }
                let items = collectItemsInFolder(sub, itemTypeID: itemType.id, collectionID: coll.id)
                collections.append(ItemCollectionSnapshot(
                    id: coll.id,
                    title: coll.title,
                    modifiedAt: coll.modifiedAt,
                    schemaVersion: coll.schemaVersion,
                    items: items
                ))
            }

            let directItems = collectItemsInFolder(folder, itemTypeID: itemType.id, collectionID: nil)

            result.append(ItemTypeSnapshot(
                id: itemType.id,
                title: itemType.title,
                icon: itemType.icon,
                modifiedAt: itemType.modifiedAt,
                schemaVersion: itemType.schemaVersion,
                properties: itemType.properties,
                collections: collections,
                directItems: directItems
            ))
        }
        return result
    }

    private static func collectItemsInFolder(
        _ folderURL: URL,
        itemTypeID: String,
        collectionID: String?
    ) -> [ItemSnapshot] {
        let urls = (try? Filesystem.children(of: folderURL) { url in
            url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
        }) ?? []
        return urls.compactMap { url -> ItemSnapshot? in
            guard let item = try? Item.load(from: url) else { return nil }
            return ItemSnapshot(
                id: item.id,
                title: item.title,
                description: item.description,
                properties: item.properties,
                modifiedAt: item.modifiedAt,
                itemTypeID: itemTypeID,
                collectionID: collectionID,
                tier1: item.tier1,
                tier2: item.tier2,
                tier3: item.tier3
            )
        }
    }

    private static func collectTasks(from nexus: Nexus) -> [AgendaTaskSnapshot] {
        let dir = NexusPaths.tasksDir(in: nexus)
        guard Filesystem.folderExists(at: dir) else { return [] }
        let urls = (try? Filesystem.children(of: dir) { url in
            url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
        }) ?? []
        return urls.compactMap { url -> AgendaTaskSnapshot? in
            guard let task = try? AgendaTask.load(from: url) else { return nil }
            return AgendaTaskSnapshot(
                id: task.id,
                title: task.title,
                dueAt: task.dueAt,
                properties: task.properties,
                modifiedAt: task.modifiedAt,
                tier1: task.tier1,
                tier2: task.tier2,
                tier3: task.tier3
            )
        }
    }

    private static func collectTaskSchema(from nexus: Nexus) -> TaskSchemaSnapshot? {
        let schemaURL = NexusPaths.taskSchemaURL(in: nexus)
        guard Filesystem.fileExists(at: schemaURL),
            let schema = try? AtomicJSON.decode(AgendaTaskSchema.self, from: schemaURL)
        else { return nil }
        return TaskSchemaSnapshot(properties: schema.properties)
    }

    private static func collectEvents(from nexus: Nexus) -> [AgendaEventSnapshot] {
        let dir = NexusPaths.eventsDir(in: nexus)
        guard Filesystem.folderExists(at: dir) else { return [] }
        let urls = (try? Filesystem.children(of: dir) { url in
            url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
        }) ?? []
        return urls.compactMap { url -> AgendaEventSnapshot? in
            guard let event = try? AgendaEvent.load(from: url) else { return nil }
            return AgendaEventSnapshot(
                id: event.id,
                title: event.title,
                startAt: event.startAt,
                endAt: event.endAt,
                properties: event.properties,
                modifiedAt: event.modifiedAt,
                tier1: event.tier1,
                tier2: event.tier2,
                tier3: event.tier3
            )
        }
    }

    private static func collectEventSchema(from nexus: Nexus) -> EventSchemaSnapshot? {
        let schemaURL = NexusPaths.eventSchemaURL(in: nexus)
        guard Filesystem.fileExists(at: schemaURL),
            let schema = try? AtomicJSON.decode(AgendaEventSchema.self, from: schemaURL)
        else { return nil }
        return EventSchemaSnapshot(properties: schema.properties)
    }

    private static func collectContexts(from nexus: Nexus) -> [ContextSnapshot] {
        var result: [ContextSnapshot] = []

        // Spaces (tier 1)
        let spacesDir = NexusPaths.spacesDir(in: nexus)
        if Filesystem.folderExists(at: spacesDir) {
            let urls = (try? Filesystem.children(of: spacesDir) { url in
                url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "space"
            }) ?? []
            for url in urls {
                guard let space = try? Space.load(from: url) else { continue }
                result.append(ContextSnapshot(id: space.id, tier: 1, title: space.title, parentTopicID: nil))
            }
        }

        // Topics (tier 2) + Projects (tier 3)
        let topicsDir = NexusPaths.topicsDir(in: nexus)
        if Filesystem.folderExists(at: topicsDir) {
            let topicFolders = (try? Filesystem.childFolders(of: topicsDir)) ?? []
            for folder in topicFolders {
                let metaURL = folder.appendingPathComponent("_topic.json")
                guard Filesystem.fileExists(at: metaURL),
                    let topic = try? Topic.load(from: metaURL)
                else { continue }
                result.append(ContextSnapshot(id: topic.id, tier: 2, title: topic.title, parentTopicID: nil))

                let projectURLs = (try? Filesystem.children(of: folder) { url in
                    url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "project"
                }) ?? []
                for url in projectURLs {
                    guard let project = try? Project.load(from: url) else { continue }
                    result.append(ContextSnapshot(id: project.id, tier: 3, title: project.title, parentTopicID: topic.id))
                }
            }
        }

        return result
    }

    // MARK: - Phase 2: DB inserts (inside @Sendable GRDB write closure — no @MainActor calls)

    private nonisolated static func clearAllTables(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM tier_links")
        try db.execute(sql: "DELETE FROM relations")
        try db.execute(sql: "DELETE FROM property_definitions")
        try db.execute(sql: "DELETE FROM pages")
        try db.execute(sql: "DELETE FROM page_collections")
        try db.execute(sql: "DELETE FROM items")
        try db.execute(sql: "DELETE FROM item_collections")
        try db.execute(sql: "DELETE FROM agenda_tasks")
        try db.execute(sql: "DELETE FROM agenda_events")
        try db.execute(sql: "DELETE FROM contexts")
        try db.execute(sql: "DELETE FROM page_types")
        try db.execute(sql: "DELETE FROM item_types")
    }

    private nonisolated static func insertPageTypes(_ db: Database, snapshot: NexusSnapshot) throws {
        for pt in snapshot.pageTypes {
            try db.execute(
                literal: """
                    INSERT INTO page_types (id, title, icon, modified_at, schema_version)
                    VALUES (\(pt.id), \(pt.title), \(pt.icon), \(iso8601(pt.modifiedAt)), \(pt.schemaVersion))
                    """
            )
            try insertPropertyDefinitions(db, properties: pt.properties,
                owningTypeID: pt.id, owningTypeKind: "page_type")

            for coll in pt.collections {
                try db.execute(
                    literal: """
                        INSERT INTO page_collections (id, page_type_id, title, modified_at, schema_version)
                        VALUES (\(coll.id), \(pt.id), \(coll.title), \(iso8601(coll.modifiedAt)), \(coll.schemaVersion))
                        """
                )
                for page in coll.pages {
                    try insertPage(db, page: page)
                }
            }
            for page in pt.directPages {
                try insertPage(db, page: page)
            }
        }
    }

    private nonisolated static func insertPage(_ db: Database, page: PageSnapshot) throws {
        let propsJSON = (try? propertiesJSON(page.properties)) ?? "{}"
        try db.execute(
            literal: """
                INSERT INTO pages (id, page_type_id, page_collection_id, title, properties, modified_at)
                VALUES (\(page.id), \(page.pageTypeID), \(page.collectionID), \(page.title), \(propsJSON), \(iso8601(page.modifiedAt)))
                """
        )
    }

    private nonisolated static func insertItemTypes(_ db: Database, snapshot: NexusSnapshot) throws {
        for it in snapshot.itemTypes {
            try db.execute(
                literal: """
                    INSERT INTO item_types (id, title, icon, modified_at, schema_version)
                    VALUES (\(it.id), \(it.title), \(it.icon), \(iso8601(it.modifiedAt)), \(it.schemaVersion))
                    """
            )
            try insertPropertyDefinitions(db, properties: it.properties,
                owningTypeID: it.id, owningTypeKind: "item_type")

            for coll in it.collections {
                try db.execute(
                    literal: """
                        INSERT INTO item_collections (id, item_type_id, title, modified_at, schema_version)
                        VALUES (\(coll.id), \(it.id), \(coll.title), \(iso8601(coll.modifiedAt)), \(coll.schemaVersion))
                        """
                )
                for item in coll.items {
                    try insertItem(db, item: item)
                }
            }
            for item in it.directItems {
                try insertItem(db, item: item)
            }
        }
    }

    private nonisolated static func insertItem(_ db: Database, item: ItemSnapshot) throws {
        let propsJSON = (try? propertiesJSON(item.properties)) ?? "{}"
        try db.execute(
            literal: """
                INSERT INTO items (id, item_type_id, item_collection_id, title, description, properties, modified_at)
                VALUES (\(item.id), \(item.itemTypeID), \(item.collectionID), \(item.title), \(item.description), \(propsJSON), \(iso8601(item.modifiedAt)))
                """
        )
    }

    private nonisolated static func insertAgendaTasks(_ db: Database, snapshot: NexusSnapshot) throws {
        if let schema = snapshot.taskSchema {
            try insertPropertyDefinitions(db, properties: schema.properties,
                owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema")
        }
        for task in snapshot.tasks {
            let propsJSON = (try? propertiesJSON(task.properties)) ?? "{}"
            try db.execute(
                literal: """
                    INSERT INTO agenda_tasks (id, title, due_at, properties, modified_at)
                    VALUES (\(task.id), \(task.title), \(task.dueAt.map { iso8601($0) }), \(propsJSON), \(iso8601(task.modifiedAt)))
                    """
            )
        }
    }

    private nonisolated static func insertAgendaEvents(_ db: Database, snapshot: NexusSnapshot) throws {
        if let schema = snapshot.eventSchema {
            try insertPropertyDefinitions(db, properties: schema.properties,
                owningTypeID: "agenda_events", owningTypeKind: "agenda_event_schema")
        }
        for event in snapshot.events {
            let propsJSON = (try? propertiesJSON(event.properties)) ?? "{}"
            try db.execute(
                literal: """
                    INSERT INTO agenda_events (id, title, start_at, end_at, properties, modified_at)
                    VALUES (\(event.id), \(event.title), \(iso8601(event.startAt)), \(iso8601(event.endAt)), \(propsJSON), \(iso8601(event.modifiedAt)))
                    """
            )
        }
    }

    private nonisolated static func insertContexts(_ db: Database, snapshot: NexusSnapshot) throws {
        for ctx in snapshot.contexts {
            try db.execute(
                literal: """
                    INSERT INTO contexts (id, tier, title, parent_topic_id)
                    VALUES (\(ctx.id), \(ctx.tier), \(ctx.title), \(ctx.parentTopicID))
                    """
            )
        }
    }

    private nonisolated static func insertRelations(_ db: Database, snapshot: NexusSnapshot) throws {
        // Pages
        for pt in snapshot.pageTypes {
            let schema = pt.properties
            for coll in pt.collections {
                for page in coll.pages {
                    try insertRelationRows(db, properties: page.properties, schema: schema,
                        sourceID: page.id, sourceKind: "page", modifiedAt: page.modifiedAt)
                }
            }
            for page in pt.directPages {
                try insertRelationRows(db, properties: page.properties, schema: schema,
                    sourceID: page.id, sourceKind: "page", modifiedAt: page.modifiedAt)
            }
        }
        // Items
        for it in snapshot.itemTypes {
            let schema = it.properties
            for coll in it.collections {
                for item in coll.items {
                    try insertRelationRows(db, properties: item.properties, schema: schema,
                        sourceID: item.id, sourceKind: "item", modifiedAt: item.modifiedAt)
                }
            }
            for item in it.directItems {
                try insertRelationRows(db, properties: item.properties, schema: schema,
                    sourceID: item.id, sourceKind: "item", modifiedAt: item.modifiedAt)
            }
        }
        // Tasks
        let taskSchema = snapshot.taskSchema?.properties ?? []
        for task in snapshot.tasks {
            try insertRelationRows(db, properties: task.properties, schema: taskSchema,
                sourceID: task.id, sourceKind: "agenda_task", modifiedAt: task.modifiedAt)
        }
        // Events
        let eventSchema = snapshot.eventSchema?.properties ?? []
        for event in snapshot.events {
            try insertRelationRows(db, properties: event.properties, schema: eventSchema,
                sourceID: event.id, sourceKind: "agenda_event", modifiedAt: event.modifiedAt)
        }
    }

    private nonisolated static func insertRelationRows(
        _ db: Database,
        properties: [String: PropertyValue],
        schema: [PropertyDefinition],
        sourceID: String,
        sourceKind: String,
        modifiedAt: Date
    ) throws {
        let schemaByID = Dictionary(uniqueKeysWithValues: schema.map { ($0.id, $0) })
        for (propID, value) in properties {
            guard case .relation(let targetIDs) = value else { continue }
            let def = schemaByID[propID]
            let targetKind = targetKindString(for: def?.relationScope)
            for targetID in targetIDs {
                let relationID = UUID().uuidString
                try db.execute(
                    literal: """
                        INSERT INTO relations (id, source_id, source_kind, target_id, target_kind, property_id, modified_at)
                        VALUES (\(relationID), \(sourceID), \(sourceKind), \(targetID), \(targetKind), \(propID), \(iso8601(modifiedAt)))
                        """
                )
            }
        }
    }

    private nonisolated static func targetKindString(for scope: PropertyDefinition.RelationScope?) -> String {
        guard let scope else { return "unknown" }
        switch scope {
        case .pageType, .pageCollection: return "page"
        case .itemType, .itemCollection: return "item"
        case .contextTier(let tier):
            switch tier {
            case 1: return "space"
            case 2: return "topic"
            case 3: return "project"
            default: return "context"
            }
        }
    }

    private nonisolated static func insertTierLinks(_ db: Database, snapshot: NexusSnapshot) throws {
        for pt in snapshot.pageTypes {
            for coll in pt.collections {
                for page in coll.pages {
                    try insertTierLinkRows(db, entityID: page.id, entityKind: "page",
                        tier1: page.tier1, tier2: page.tier2, tier3: page.tier3)
                }
            }
            for page in pt.directPages {
                try insertTierLinkRows(db, entityID: page.id, entityKind: "page",
                    tier1: page.tier1, tier2: page.tier2, tier3: page.tier3)
            }
        }
        for it in snapshot.itemTypes {
            for coll in it.collections {
                for item in coll.items {
                    try insertTierLinkRows(db, entityID: item.id, entityKind: "item",
                        tier1: item.tier1, tier2: item.tier2, tier3: item.tier3)
                }
            }
            for item in it.directItems {
                try insertTierLinkRows(db, entityID: item.id, entityKind: "item",
                    tier1: item.tier1, tier2: item.tier2, tier3: item.tier3)
            }
        }
        for task in snapshot.tasks {
            try insertTierLinkRows(db, entityID: task.id, entityKind: "agenda_task",
                tier1: task.tier1, tier2: task.tier2, tier3: task.tier3)
        }
        for event in snapshot.events {
            try insertTierLinkRows(db, entityID: event.id, entityKind: "agenda_event",
                tier1: event.tier1, tier2: event.tier2, tier3: event.tier3)
        }
    }

    private nonisolated static func insertTierLinkRows(
        _ db: Database,
        entityID: String,
        entityKind: String,
        tier1: [String],
        tier2: [String],
        tier3: [String]
    ) throws {
        for targetID in tier1 {
            try db.execute(literal: "INSERT OR IGNORE INTO tier_links (entity_id, entity_kind, tier, target_id) VALUES (\(entityID), \(entityKind), 1, \(targetID))")
        }
        for targetID in tier2 {
            try db.execute(literal: "INSERT OR IGNORE INTO tier_links (entity_id, entity_kind, tier, target_id) VALUES (\(entityID), \(entityKind), 2, \(targetID))")
        }
        for targetID in tier3 {
            try db.execute(literal: "INSERT OR IGNORE INTO tier_links (entity_id, entity_kind, tier, target_id) VALUES (\(entityID), \(entityKind), 3, \(targetID))")
        }
    }

    private nonisolated static func insertPropertyDefinitions(
        _ db: Database,
        properties: [PropertyDefinition],
        owningTypeID: String,
        owningTypeKind: String
    ) throws {
        for (position, def) in properties.enumerated() {
            guard !def.id.isEmpty else { continue }
            let configJSON = (try? definitionConfigJSON(def)) ?? "{}"
            let modAt = iso8601(Date())
            try db.execute(
                literal: """
                    INSERT INTO property_definitions
                        (id, owning_type_id, owning_type_kind, name, type, config, position, modified_at)
                    VALUES (\(def.id), \(owningTypeID), \(owningTypeKind), \(def.name), \(def.type.rawValue), \(configJSON), \(position), \(modAt))
                    """
            )
        }
    }

    // MARK: - Encoding helpers (nonisolated — pure computation, no domain-type calls)

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private nonisolated static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private nonisolated static func propertiesJSON(_ properties: [String: PropertyValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(properties)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private nonisolated static func definitionConfigJSON(_ def: PropertyDefinition) throws -> String {
        struct ConfigOnly: Encodable {
            var numberFormat: PropertyDefinition.NumberFormat?
            var dateIncludesTime: Bool?
            var selectOptions: [PropertyDefinition.SelectOption]?
            var statusGroups: [PropertyDefinition.StatusGroup]?
            var relationScope: PropertyDefinition.RelationScope?
            var allowsMultiple: Bool?
            var accept: [String]?

            enum CodingKeys: String, CodingKey {
                case numberFormat = "number_format"
                case dateIncludesTime = "date_includes_time"
                case selectOptions = "select_options"
                case statusGroups = "status_groups"
                case relationScope = "relation_scope"
                case allowsMultiple = "allows_multiple"
                case accept
            }
        }
        let config = ConfigOnly(
            numberFormat: def.numberFormat,
            dateIncludesTime: def.dateIncludesTime,
            selectOptions: def.selectOptions,
            statusGroups: def.statusGroups,
            relationScope: def.relationScope,
            allowsMultiple: def.allowsMultiple,
            accept: def.accept
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(config)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
