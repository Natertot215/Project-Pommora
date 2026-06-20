import Foundation
import GRDB
import os

/// Per-mutation writes to the SQLite index. Called post-commit by every
/// manager CRUD method. Failures here are non-fatal — log via `pendingError`
/// on the owning manager; the filesystem is canonical and the index can be
/// rebuilt via `IndexBuilder` (Phase E.4).
///
/// Upserts are idempotent so concurrent manager writes are safe. Leaf rows
/// (pages / agenda / contexts / property_definitions) use
/// `INSERT OR REPLACE`. The cascade-PARENT tables (page_types /
/// page_collections) use `INSERT ... ON CONFLICT(id) DO UPDATE`
/// instead: `INSERT OR REPLACE` DELETEs the existing row first, which fires the
/// child FKs' `ON DELETE CASCADE` / `ON DELETE SET NULL` and would wipe (or NULL)
/// every child page on a re-sync. `ON CONFLICT DO UPDATE` updates in place,
/// so no cascade fires. Relation reconciliation does a full DELETE then re-insert
/// for the source entity — correct because the source entity is always written
/// atomically before the index call.
struct IndexUpdater: Sendable {
    let index: PommoraIndex

    init(_ index: PommoraIndex) {
        self.index = index
    }

    private nonisolated static let log = Logger(subsystem: "Pommora", category: "IndexUpdater")

    // MARK: - ISO-8601 helpers

    private func iso(_ date: Date) -> String {
        IndexDateFormat.iso8601.string(from: date)
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
                    INSERT INTO page_types
                        (id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title, icon = excluded.icon,
                        modified_at = excluded.modified_at, schema_version = excluded.schema_version
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
                    INSERT INTO page_collections
                        (id, page_type_id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        page_type_id = excluded.page_type_id, title = excluded.title,
                        icon = excluded.icon, modified_at = excluded.modified_at,
                        schema_version = excluded.schema_version
                    """,
                arguments: [pc.id, pc.typeID, pc.title, pc.icon, iso(pc.modifiedAt), pc.schemaVersion]
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

    // MARK: - PageSet

    func upsertPageSet(_ set: PageSet) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO page_sets
                        (id, page_collection_id, title, icon, modified_at, schema_version)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        page_collection_id = excluded.page_collection_id, title = excluded.title,
                        icon = excluded.icon, modified_at = excluded.modified_at,
                        schema_version = excluded.schema_version
                    """,
                arguments: [set.id, set.collectionID, set.title, set.icon, iso(set.modifiedAt), set.schemaVersion]
            )
        }
    }

    func deletePageSet(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM page_sets WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Page

    func upsertPage(
        _ meta: PageMeta,
        pageTypeID: String,
        pageCollectionID: String?,
        pageSetID: String? = nil
    ) throws {
        let propsJSON = propertiesJSON(meta.frontmatter.properties)
        let modifiedAt =
            (try? FileManager.default.attributesOfItem(atPath: meta.url.path)[.modificationDate] as? Date).map {
                iso($0)
            } ?? nowISO()
        func write(collectionID: String?, setID: String?) throws {
            try index.dbQueue.write { db in
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO pages
                            (id, page_type_id, page_collection_id, page_set_id, title, icon, properties, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        meta.id, pageTypeID, collectionID, setID, meta.title, meta.frontmatter.icon, propsJSON,
                        modifiedAt,
                    ]
                )
                try reconcileContextLinks(
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
        // The index is a regeneratable cache — a parent (page_type / page_collection /
        // page_set) that isn't indexed yet must NEVER be fatal (it surfaced as the
        // "FOREIGN KEY constraint failed" toast). Fall back scope by scope: drop the
        // set first (keep the Collection), then the collection too (keep the Vault);
        // if the Vault itself is missing, skip + log.
        do {
            try write(collectionID: pageCollectionID, setID: pageSetID)
            return
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            Self.log.error(
                "upsertPage FK violation for page \(meta.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
        if pageSetID != nil {
            do {
                try write(collectionID: pageCollectionID, setID: nil)
                return
            } catch {
                Self.log.error(
                    "upsertPage FK violation for page \(meta.id, privacy: .public) without set: \(String(describing: error), privacy: .public)"
                )
            }
        }
        guard pageCollectionID != nil else { return }
        do {
            try write(collectionID: nil, setID: nil)
        } catch {
            Self.log.error(
                "upsertPage skipped page \(meta.id, privacy: .public) — parent type unindexed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func deletePage(id: String) throws {
        try index.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pages WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM context_links WHERE source_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM connections WHERE source_id = ?", arguments: [id])
        }
    }

    /// Page ids the index currently holds for one scope — a Type root excludes its
    /// Collection/Set pages, a Collection excludes its Set pages. The surgical
    /// reconcile uses this to delete rows whose file vanished from the scope.
    func pageIDs(pageTypeID: String, pageCollectionID: String?, pageSetID: String?) throws
        -> [String]
    {
        try index.dbQueue.read { db in
            if let pageSetID {
                return try String.fetchAll(
                    db, sql: "SELECT id FROM pages WHERE page_set_id = ?", arguments: [pageSetID])
            }
            if let pageCollectionID {
                return try String.fetchAll(
                    db,
                    sql: "SELECT id FROM pages WHERE page_collection_id = ? AND page_set_id IS NULL",
                    arguments: [pageCollectionID])
            }
            return try String.fetchAll(
                db,
                sql:
                    "SELECT id FROM pages WHERE page_type_id = ? AND page_collection_id IS NULL AND page_set_id IS NULL",
                arguments: [pageTypeID])
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
            try reconcileContextLinks(
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
            try reconcileContextLinks(
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

    func upsertContext(_ area: Area) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO contexts
                        (id, tier, title, icon)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [area.id, 1, area.title, area.icon]
            )
        }
    }

    func upsertContext(_ topic: Topic) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO contexts
                        (id, tier, title, icon)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [topic.id, 2, topic.title, topic.icon]
            )
        }
    }

    func upsertContext(_ project: Project) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO contexts
                        (id, tier, title, icon)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [project.id, 3, project.title, project.icon]
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

    // MARK: - Private: context-link + tier-link reconciliation

    /// Extracts all `.relation([ids])` values from `properties` and re-indexes them
    /// in the `context_links` table for `sourceID` (one row per target id). Clears existing rows first —
    /// ensures removed relation values are cleaned up cleanly. Tier values
    /// (`tier1`/`tier2`/`tier3`) are mirrored into the same `context_links` table here —
    /// after the DELETE, so the new rows survive — letting the reverse-view query
    /// (`IndexQuery.incomingContextLinks`, which reads `context_links`) surface tier-based
    /// links to a Context.
    private func reconcileContextLinks(
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
            // `target_kind` via the shared mapper (DRY): tier 1→"area" / 2→"topic" / 3→"project".
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

    // MARK: - Connections (body-scanned inline links)

    /// Re-index every `[[ ]]` in `body` for `sourceID`. Delete-then-insert
    /// (mirrors reconcileContextLinks). A target resolves only when EXACTLY one
    /// page holds the title (0 / >1 → phantom). Self-links skipped.
    func reconcileConnections(sourceID: String, sourceKind: String, sourceTitle: String, body: String) throws {
        let scanned = ConnectionScanner.scan(body: body)          // off the write closure
        let selfKey = ConnectionTitle.normalize(sourceTitle)
        let surface = "page_body"
        try index.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM connections WHERE source_id = ?", arguments: [sourceID])
            for c in scanned {
                // Self-connection guard: same kind + same title = the source itself.
                if sourceKind == "page" && c.normalizedTitle == selfKey { continue }
                let matches = try String.fetchAll(
                    db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE", arguments: [c.normalizedTitle])
                let targetID: String? = matches.count == 1 ? matches[0] : nil
                try db.execute(
                    sql: """
                        INSERT INTO connections
                            (id, source_id, source_kind, target_id, target_kind, target_title,
                             surface, multiplicity, weight, resolved, modified_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1.0, ?, ?)
                        """,
                    arguments: [ULID.generate(), sourceID, sourceKind, targetID, "page",
                                c.normalizedTitle, surface, c.multiplicity, targetID != nil ? 1 : 0, nowISO()])
            }
        }
    }

    /// A new/renamed entity's title appeared → activate matching phantom edges, but
    /// ONLY when exactly one entity now holds the title (an adopted duplicate must
    /// stay phantom). Safe because in-app uniqueness guarantees one holder.
    func activateConnections(targetID: String, targetKind: String, targetTitle: String) throws {
        let key = ConnectionTitle.normalize(targetTitle)
        try index.dbQueue.write { db in
            let holders = try String.fetchAll(
                db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE", arguments: [key])
            guard holders.count == 1 else { return }
            try db.execute(
                sql: """
                    UPDATE connections SET target_id = ?, resolved = 1, modified_at = ?
                    WHERE target_kind = ? AND target_title = ? AND target_id IS NULL
                    """,
                arguments: [targetID, nowISO(), targetKind, key])
        }
    }

    /// A permanently-deleted target → revert its inbound edges to phantom (inert).
    func deactivateConnections(targetID: String) throws {
        try index.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE connections SET target_id = NULL, resolved = 0, modified_at = ? WHERE target_id = ?",
                arguments: [nowISO(), targetID])
        }
    }

    /// After a delete, if the deleted title now has exactly ONE holder, activate
    /// that survivor's inbound phantoms (spec: activation is automatic the moment a
    /// matching entity exists — resolves a previously-ambiguous adopted duplicate).
    func reactivateIfNowUnique(targetKind: String, title: String) throws {
        let key = ConnectionTitle.normalize(title)
        try index.dbQueue.write { db in
            let ids = try String.fetchAll(
                db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE", arguments: [key])
            guard ids.count == 1 else { return }
            try db.execute(
                sql: """
                    UPDATE connections SET target_id = ?, resolved = 1, modified_at = ?
                    WHERE target_kind = ? AND target_title = ? AND target_id IS NULL
                    """,
                arguments: [ids[0], nowISO(), targetKind, key])
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
