import Foundation
import GRDB
import os

/// Per-mutation writes to the SQLite index. Called post-commit by every
/// manager CRUD method. Failures here are non-fatal — log via `pendingError`
/// on the owning manager; the filesystem is canonical and the index can be
/// rebuilt via `IndexBuilder` (Phase E.4).
///
/// All upserts use `INSERT OR REPLACE INTO ...` so concurrent manager writes
/// are idempotent. Relation reconciliation does a full DELETE then re-insert
/// for the source entity — correct because the source entity is always written
/// atomically before the index call.
struct IndexUpdater: Sendable {
    let index: PommoraIndex

    init(_ index: PommoraIndex) {
        self.index = index
    }

    private nonisolated static let log = Logger(subsystem: "Pommora", category: "IndexUpdater")

    // MARK: - ISO-8601 helpers

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso(_ date: Date) -> String {
        IndexUpdater.iso8601.string(from: date)
    }

    private func nowISO() -> String {
        iso(Date())
    }

    // MARK: - JSON helpers

    private static let jsonEncoder: JSONEncoder = JSONEncoder()

    private func propertiesJSON(_ properties: [String: PropertyValue]) -> String {
        guard
            let data = try? IndexUpdater.jsonEncoder.encode(properties),
            let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }

    // MARK: - PageType

    func upsertPageType(_ pt: PageType) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO page_types
                        (id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [pt.id, pt.title, pt.icon, iso(pt.modifiedAt), pt.schemaVersion]
            )
        }
    }

    func deletePageType(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM page_types WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - PageCollection

    func upsertPageCollection(_ pc: PageCollection) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO page_collections
                        (id, page_type_id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [pc.id, pc.typeID, pc.title, pc.icon, iso(pc.modifiedAt), 1]
            )
        }
    }

    func deletePageCollection(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM page_collections WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Page

    func upsertPage(
        _ meta: PageMeta,
        pageTypeID: String,
        pageCollectionID: String?
    ) throws {
        let propsJSON = propertiesJSON(meta.frontmatter.properties)
        let modifiedAt =
            (try? FileManager.default.attributesOfItem(atPath: meta.url.path)[.modificationDate] as? Date).map {
                iso($0)
            } ?? nowISO()
        func write(collectionID: String?) throws {
            try index.dbQueue.write { db in
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO pages
                            (id, page_type_id, page_collection_id, title, icon, properties, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        meta.id, pageTypeID, collectionID, meta.title, meta.frontmatter.icon, propsJSON, modifiedAt,
                    ]
                )
                try reconcileRelations(
                    db: db,
                    sourceID: meta.id,
                    sourceKind: "page",
                    properties: meta.frontmatter.properties,
                    tier1: meta.frontmatter.tier1,
                    tier2: meta.frontmatter.tier2,
                    tier3: meta.frontmatter.tier3
                )
            }
        }
        do {
            try write(collectionID: pageCollectionID)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            // The index is a regeneratable cache — a parent (page_type / page_collection)
            // that isn't indexed yet must NEVER be fatal (it surfaced as the
            // "FOREIGN KEY constraint failed" toast). If only the collection is missing,
            // retry without it so the page still indexes under its Vault; if the Vault
            // itself is missing, skip + log.
            Self.log.error(
                "upsertPage FK violation for page \(meta.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            guard pageCollectionID != nil else { return }
            do {
                try write(collectionID: nil)
            } catch {
                Self.log.error(
                    "upsertPage skipped page \(meta.id, privacy: .public) — parent type unindexed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    func deletePage(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pages WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM context_links WHERE source_id = ?", arguments: [id])
        }
    }

    // MARK: - ItemType

    func upsertItemType(_ it: ItemType) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO item_types
                        (id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [it.id, it.title, it.icon, iso(it.modifiedAt), it.schemaVersion]
            )
        }
    }

    func deleteItemType(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM item_types WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - ItemCollection

    func upsertItemCollection(_ ic: ItemCollection) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO item_collections
                        (id, item_type_id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [ic.id, ic.typeID, ic.title, ic.icon, iso(ic.modifiedAt), 1]
            )
        }
    }

    func deleteItemCollection(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM item_collections WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Item

    func upsertItem(_ item: Item, itemTypeID: String, itemCollectionID: String?) throws {
        let propsJSON = propertiesJSON(item.properties)
        func write(collectionID: String?) throws {
            try index.dbQueue.write { db in
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO items
                            (id, item_type_id, item_collection_id, title, icon, description, properties, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        item.id, itemTypeID, collectionID,
                        item.title, item.icon, item.description, propsJSON, iso(item.modifiedAt),
                    ]
                )
                try reconcileRelations(
                    db: db,
                    sourceID: item.id,
                    sourceKind: "item",
                    properties: item.properties,
                    tier1: item.tier1,
                    tier2: item.tier2,
                    tier3: item.tier3
                )
            }
        }
        do {
            try write(collectionID: itemCollectionID)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            // Mirror of upsertPage: a missing parent must never be fatal. Retry without
            // the (missing) collection so the item still indexes under its Type; if the
            // Type itself is missing, skip + log.
            Self.log.error(
                "upsertItem FK violation for item \(item.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            guard itemCollectionID != nil else { return }
            do {
                try write(collectionID: nil)
            } catch {
                Self.log.error(
                    "upsertItem skipped item \(item.id, privacy: .public) — parent type unindexed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    func deleteItem(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM context_links WHERE source_id = ?", arguments: [id])
        }
    }

    // MARK: - AgendaTask

    func upsertAgendaTask(_ task: AgendaTask) throws {
        let propsJSON = propertiesJSON(task.properties)
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO agenda_tasks
                        (id, title, icon, due_at, properties, modified_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    task.id, task.title, task.icon,
                    task.dueAt.map { iso($0) },
                    propsJSON, iso(task.modifiedAt),
                ]
            )
            try reconcileRelations(
                db: db,
                sourceID: task.id,
                sourceKind: "agenda_task",
                properties: task.properties,
                tier1: task.tier1,
                tier2: task.tier2,
                tier3: task.tier3
            )
        }
    }

    func deleteAgendaTask(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM agenda_tasks WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM context_links WHERE source_id = ?", arguments: [id])
        }
    }

    // MARK: - AgendaEvent

    func upsertAgendaEvent(_ event: AgendaEvent) throws {
        let propsJSON = propertiesJSON(event.properties)
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO agenda_events
                        (id, title, icon, start_at, end_at, properties, modified_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    event.id, event.title, event.icon,
                    iso(event.startAt), iso(event.endAt),
                    propsJSON, iso(event.modifiedAt),
                ]
            )
            try reconcileRelations(
                db: db,
                sourceID: event.id,
                sourceKind: "agenda_event",
                properties: event.properties,
                tier1: event.tier1,
                tier2: event.tier2,
                tier3: event.tier3
            )
        }
    }

    func deleteAgendaEvent(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM agenda_events WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM context_links WHERE source_id = ?", arguments: [id])
        }
    }

    // MARK: - Contexts

    func upsertContext(_ space: Space) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO contexts
                        (id, tier, title, icon, parent_topic_id)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [space.id, 1, space.title, space.icon, nil]
            )
        }
    }

    func upsertContext(_ topic: Topic) throws {
        try index.dbQueue.write { db in
            // Topics may have multiple parents — index first parent (or nil).
            let firstParent = topic.parents.first
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO contexts
                        (id, tier, title, icon, parent_topic_id)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [topic.id, 2, topic.title, topic.icon, firstParent]
            )
        }
    }

    func upsertContext(_ project: Project) throws {
        try index.dbQueue.write { db in
            let parentTopicID = project.parents.first
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO contexts
                        (id, tier, title, icon, parent_topic_id)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [project.id, 3, project.title, project.icon, parentTopicID]
            )
        }
    }

    func deleteContext(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM contexts WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - PropertyDefinition

    func upsertPropertyDefinition(
        _ def: PropertyDefinition,
        owningTypeID: String,
        owningTypeKind: String,
        position: Int
    ) throws {
        let configJSON = configJSON(for: def)
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO property_definitions
                        (id, owning_type_id, owning_type_kind, name, type, config, position, modified_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    def.id, owningTypeID, owningTypeKind,
                    def.name, def.type.rawValue,
                    configJSON, position, nowISO(),
                ]
            )
        }
    }

    func deletePropertyDefinition(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM property_definitions WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Private: relation + tier-link reconciliation

    /// Extracts all `.relation([ids])` values from `properties` and re-indexes them
    /// in the `context_links` table for `sourceID` (one row per target id). Clears existing rows first —
    /// ensures removed relation values are cleaned up cleanly. Tier values
    /// (`tier1`/`tier2`/`tier3`) are mirrored into the same `context_links` table here —
    /// after the DELETE, so the new rows survive — letting the reverse-view query
    /// (`IndexQuery.incomingRelations`, which reads `context_links`) surface tier-based
    /// links to a Context.
    private func reconcileRelations(
        db: Database,
        sourceID: String,
        sourceKind: String,
        properties: [String: PropertyValue],
        tier1: [String],
        tier2: [String],
        tier3: [String]
    ) throws {
        try db.execute(
            sql: "DELETE FROM context_links WHERE source_id = ?",
            arguments: [sourceID]
        )
        // Tier relations — emitted after the DELETE above so they aren't wiped.
        let tiers: [(Int, [String], String)] = [
            (1, tier1, ReservedPropertyID.tier1),
            (2, tier2, ReservedPropertyID.tier2),
            (3, tier3, ReservedPropertyID.tier3),
        ]
        for (level, targetIDs, propertyID) in tiers {
            // `target_kind` via the shared mapper (DRY): tier 1→"space" / 2→"topic" / 3→"project".
            let targetKind = RelationTargetKind.string(from: .contextTier(level))
            for targetID in targetIDs {
                let relID = ULID.generate()
                try db.execute(
                    sql: """
                        INSERT INTO context_links
                            (id, source_id, source_kind, target_id, target_kind, property_id, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        relID, sourceID, sourceKind,
                        targetID, targetKind,
                        propertyID, nowISO(),
                    ]
                )
            }
        }
    }

    // MARK: - Private: config JSON

    /// Serialises type-specific config fields into the `config` JSON blob
    /// stored in `property_definitions.config`. Delegates to the single source
    /// of truth shared with `IndexBuilder` so rows written by either path
    /// round-trip identically.
    private func configJSON(for def: PropertyDefinition) -> String {
        def.indexConfigJSON()
    }
}
