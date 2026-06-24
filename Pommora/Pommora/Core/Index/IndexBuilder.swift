import Foundation
import GRDB
import os

// MARK: - Sendable snapshot types (pure data, passed across actor boundaries)

/// Snapshot of a PageCollection and its children, safe to pass into a @Sendable closure.
private struct PageCollectionSnapshot: Sendable {
    let id: String
    let title: String
    let icon: String?
    let modifiedAt: Date
    let schemaVersion: Int
    let properties: [PropertyDefinition]
    let sets: [PageSetSnapshot]
    let directPages: [PageSnapshot]
}

private struct PageSetSnapshot: Sendable {
    let id: String
    let title: String
    let icon: String?
    let modifiedAt: Date
    let schemaVersion: Int
    // exactly one of parentCollectionID / parentSetID is non-nil
    let parentCollectionID: String?
    let parentSetID: String?
    let children: [PageSetSnapshot]
    let pages: [PageSnapshot]
}

private struct PageSnapshot: Sendable {
    let id: String
    let title: String
    let icon: String?
    let body: String
    let properties: [String: PropertyValue]
    let modifiedAt: Date
    let pageCollectionID: String
    let setID: String?
    let tier1: [String]
    let tier2: [String]
    let tier3: [String]
}

private struct AgendaTaskSnapshot: Sendable {
    let id: String
    let title: String
    let icon: String?
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
    let icon: String?
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
    let icon: String?
}

private struct TaskSchemaSnapshot: Sendable {
    let properties: [PropertyDefinition]
}

private struct EventSchemaSnapshot: Sendable {
    let properties: [PropertyDefinition]
}

private struct NexusSnapshot: Sendable {
    let pageCollections: [PageCollectionSnapshot]
    let tasks: [AgendaTaskSnapshot]
    let taskSchema: TaskSchemaSnapshot?
    let events: [AgendaEventSnapshot]
    let eventSchema: EventSchemaSnapshot?
    let contexts: [ContextSnapshot]
}

// MARK: - IndexBuilder

/// Populates a fresh PommoraIndex from on-disk Nexus content. Used on first
/// launch + on schema_version mismatch (rebuild) + on explicit "rebuild index"
/// from Settings.
///
/// Strategy: `clearAllTables` then re-insert everything inside one transaction.
/// Each row insert is *resilient* — a single bad on-disk row (a duplicate
/// primary key from a legacy/adoption id collision, an orphaned foreign key) is
/// skipped + logged via `attemptInsert` rather than aborting the whole rebuild.
/// SQLite's default `ABORT` conflict resolution rolls back only the failing
/// statement, so the surrounding transaction stays alive and every *valid*
/// entity — notably the Contexts that back the tier pickers — still lands.
/// Since the DB is a regeneratable index (no user data), skipping a malformed
/// row is safe; the canonical fix is to repair the file on disk.
final class IndexBuilder {

    // MARK: - Public API

    /// Walks `nexus`'s on-disk content and populates `index`'s tables.
    /// Throws on filesystem read failure or DB write failure.
    /// `filter` prunes excluded user folders from page-type discovery;
    /// defaults to `.empty` (no exclusions) so existing callers
    /// and tests that don't need filtering are unaffected.
    static func populate(index: PommoraIndex, from nexus: Nexus, filter: FolderFilter = .empty) async throws {
        // Phase 1: Walk the filesystem on the @MainActor (domain types are @MainActor-isolated).
        let snapshot = buildSnapshot(from: nexus, filter: filter)

        // Phase 2: Write collected data into the DB inside a @Sendable closure.
        // No @MainActor calls happen inside here — all data is pre-collected in `snapshot`.
        try await index.dbQueue.write { db in
            try clearAllTables(db)
            insertPageCollections(db, snapshot: snapshot)
            insertAgendaTasks(db, snapshot: snapshot)
            insertAgendaEvents(db, snapshot: snapshot)
            insertContexts(db, snapshot: snapshot)
            insertTierContextLinks(db, snapshot: snapshot)
            insertConnections(db, snapshot: snapshot)
        }
    }

    // MARK: - Phase 1: Filesystem walk (runs on @MainActor)

    private static func buildSnapshot(from nexus: Nexus, filter: FolderFilter = .empty) -> NexusSnapshot {
        NexusSnapshot(
            pageCollections: collectPageCollections(from: nexus, filter: filter),
            tasks: collectTasks(from: nexus),
            taskSchema: collectTaskSchema(from: nexus),
            events: collectEvents(from: nexus),
            eventSchema: collectEventSchema(from: nexus),
            contexts: collectContexts(from: nexus)
        )
    }

    private static func collectPageCollections(from nexus: Nexus, filter: FolderFilter = .empty) -> [PageCollectionSnapshot] {
        let root = nexus.rootURL
        let topLevel = (try? Filesystem.childFolders(of: root, folderFilter: filter)) ?? []
        var result: [PageCollectionSnapshot] = []

        for folder in topLevel
        where !folder.lastPathComponent.hasPrefix(".") && !folder.lastPathComponent.hasPrefix("_") {
            let metaURL = folder.appendingPathComponent(NexusPaths.pageCollectionSidecarFilename)
            guard Filesystem.fileExists(at: metaURL),
                let pc = try? PageCollection.load(from: metaURL)
            else { continue }

            // Depth-1 sets — sub-folders of the Collection carrying `_pageset.json`.
            let subFolders = (try? Filesystem.childFolders(of: folder, folderFilter: filter)) ?? []
            var depthOneSets: [PageSetSnapshot] = []
            for sub in subFolders where !sub.lastPathComponent.hasPrefix("_") && !sub.lastPathComponent.hasPrefix(".") {
                let setURL = sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
                guard Filesystem.fileExists(at: setURL),
                    let set = try? PageSet.load(from: setURL)
                else { continue }

                let snap = collectSetSnapshot(
                    set, folder: sub, parentCollectionID: pc.id, parentSetID: nil,
                    pageCollectionID: pc.id, nexusRoot: root, filter: filter)
                depthOneSets.append(snap)
            }

            let directPages = collectPagesInFolder(
                folder, pageCollectionID: pc.id, nexusRoot: root, filter: filter)

            result.append(
                PageCollectionSnapshot(
                    id: pc.id,
                    title: pc.title,
                    icon: pc.icon,
                    modifiedAt: pc.modifiedAt,
                    schemaVersion: pc.schemaVersion,
                    properties: pc.properties,
                    sets: depthOneSets,
                    directPages: directPages
                ))
        }
        return result
    }

    /// Recursively builds a `PageSetSnapshot` for `set`, walking child sub-folders
    /// at any depth. Depth-1 sets carry `parentTypeID`; deeper sets carry `parentSetID`.
    private static func collectSetSnapshot(
        _ set: PageSet,
        folder: URL,
        parentCollectionID: String?,
        parentSetID: String?,
        pageCollectionID: String,
        nexusRoot: URL,
        filter: FolderFilter
    ) -> PageSetSnapshot {
        let subFolders = (try? Filesystem.childFolders(of: folder, folderFilter: filter)) ?? []
        var children: [PageSetSnapshot] = []
        for sub in subFolders where !sub.lastPathComponent.hasPrefix("_") && !sub.lastPathComponent.hasPrefix(".") {
            let subSetURL = sub.appendingPathComponent(NexusPaths.pageSetSidecarFilename)
            guard Filesystem.fileExists(at: subSetURL),
                let child = try? PageSet.load(from: subSetURL)
            else { continue }
            let childSnap = collectSetSnapshot(
                child, folder: sub, parentCollectionID: nil, parentSetID: set.id,
                pageCollectionID: pageCollectionID, nexusRoot: nexusRoot, filter: filter)
            children.append(childSnap)
        }
        let pages = collectPagesInFolder(
            folder, pageCollectionID: pageCollectionID, setID: set.id,
            nexusRoot: nexusRoot, filter: filter)
        return PageSetSnapshot(
            id: set.id,
            title: set.title,
            icon: set.icon,
            modifiedAt: set.modifiedAt,
            schemaVersion: set.schemaVersion,
            parentCollectionID: parentCollectionID,
            parentSetID: parentSetID,
            children: children,
            pages: pages
        )
    }

    private static func collectPagesInFolder(
        _ folderURL: URL,
        pageCollectionID: String,
        setID: String? = nil,
        nexusRoot: URL,
        filter: FolderFilter
    ) -> [PageSnapshot] {
        // User folder-exclusion veto applied at the FILE level — mirrors loadAll's
        // `descendantFiles(folderFilter:)` so a `.nexus/settings.json` excluded_folders
        // entry (a folder, OR a loose file path like "Pommora/CLAUDE.md") keeps that
        // content out of the index exactly as it's kept out of the sidebar.
        let urls =
            (try? Filesystem.children(of: folderURL) { url in
                url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
            })?.filter { !filter.isExcluded($0) } ?? []
        return urls.compactMap { url -> PageSnapshot? in
            // Lenient load mirrors the UI discovery contract
            // (PageContentManager.loadAll → PageFile.loadLenient): an adopted `.md`
            // Page without Pommora frontmatter MUST index at launch, or wiki-link
            // resolution can't find it by title until an unrelated CRUD write
            // incidentally upserts it. The strict `PageFile.load` silently dropped
            // every frontmatter-less page from the launch scan.
            guard let loaded = try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot)
            else { return nil }
            // Stamp a frontmatter-less Page with a stable ULID at index-build time
            // (Obsidian import / rebuild) so the snapshot — and any future rename —
            // tracks by a persisted id rather than a path-derived placeholder.
            let pf = PageStamper.stampInPlace(loaded, at: url)
            let fm = pf.frontmatter
            return PageSnapshot(
                id: fm.id,
                title: pf.title,
                icon: fm.icon,
                body: pf.body,
                properties: fm.properties,
                modifiedAt: fm.modifiedAt ?? fm.createdAt,
                pageCollectionID: pageCollectionID,
                setID: setID,
                tier1: fm.tier1,
                tier2: fm.tier2,
                tier3: fm.tier3
            )
        }
    }

    private static func collectTasks(from nexus: Nexus) -> [AgendaTaskSnapshot] {
        let dir = NexusPaths.tasksDir(in: nexus)
        guard Filesystem.folderExists(at: dir) else { return [] }
        let urls =
            (try? Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
            }) ?? []
        return urls.compactMap { url -> AgendaTaskSnapshot? in
            guard let task = try? AgendaTask.load(from: url) else { return nil }
            return AgendaTaskSnapshot(
                id: task.id,
                title: task.title,
                icon: task.icon,
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
        let urls =
            (try? Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
            }) ?? []
        return urls.compactMap { url -> AgendaEventSnapshot? in
            guard let event = try? AgendaEvent.load(from: url) else { return nil }
            return AgendaEventSnapshot(
                id: event.id,
                title: event.title,
                icon: event.icon,
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

        // Areas (tier 1)
        let areasDir = NexusPaths.areasDir(in: nexus)
        if Filesystem.folderExists(at: areasDir) {
            let areaFolders = (try? Filesystem.childFolders(of: areasDir)) ?? []
            for folder in areaFolders {
                let metaURL = folder.appendingPathComponent("_area.json")
                guard Filesystem.fileExists(at: metaURL),
                    let area = try? Area.load(from: metaURL)
                else { continue }
                result.append(
                    ContextSnapshot(id: area.id, tier: 1, title: area.title, icon: area.icon))
            }
        }

        // Topics (tier 2)
        let topicsDir = NexusPaths.topicsDir(in: nexus)
        if Filesystem.folderExists(at: topicsDir) {
            let topicFolders = (try? Filesystem.childFolders(of: topicsDir)) ?? []
            for folder in topicFolders {
                let metaURL = folder.appendingPathComponent("_topic.json")
                guard Filesystem.fileExists(at: metaURL),
                    let topic = try? Topic.load(from: metaURL)
                else { continue }
                result.append(
                    ContextSnapshot(id: topic.id, tier: 2, title: topic.title, icon: topic.icon))
            }
        }

        // Projects (tier 3) — free-standing folders
        let projectsDir = NexusPaths.projectsDir(in: nexus)
        if Filesystem.folderExists(at: projectsDir) {
            let projectFolders = (try? Filesystem.childFolders(of: projectsDir)) ?? []
            for folder in projectFolders {
                let metaURL = folder.appendingPathComponent("_project.json")
                guard Filesystem.fileExists(at: metaURL),
                    let project = try? Project.load(from: metaURL)
                else { continue }
                result.append(
                    ContextSnapshot(id: project.id, tier: 3, title: project.title, icon: project.icon))
            }
        }

        return result
    }

    // MARK: - Phase 2: DB inserts (inside @Sendable GRDB write closure — no @MainActor calls)

    /// Rebuild diagnostics. A skipped row is logged here (visible in Console.app)
    /// rather than surfaced as a user-facing error — the index is a regeneratable
    /// cache, so a malformed on-disk row is non-fatal.
    private nonisolated static let log = Logger(subsystem: "Pommora", category: "IndexBuilder")

    /// Runs a single index insert in isolation so one bad on-disk row can't
    /// abort the whole rebuild. SQLite's default `ABORT` conflict resolution
    /// rolls back only the *failing statement* — the enclosing `populate`
    /// transaction stays alive — so a duplicate primary key or an orphaned
    /// foreign key is skipped + logged instead of rolling the WHOLE rebuild back
    /// and leaving the index (and its Contexts) empty. Returns `true` on success
    /// so a caller can skip a parent's subtree when the parent itself fails.
    @discardableResult
    private nonisolated static func attemptInsert(
        _ describe: @autoclosure () -> String,
        _ insert: () throws -> Void
    ) -> Bool {
        do {
            try insert()
            return true
        } catch {
            // Evaluate the (non-escaping) autoclosure into a plain String first:
            // Logger.error takes its message as an @escaping autoclosure, which
            // can't capture a non-escaping parameter directly. Binding here keeps
            // the deferral — `describe()` still only runs on the failure path.
            let detail = describe()
            log.error(
                "Index rebuild skipped \(detail, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private nonisolated static func clearAllTables(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM connections")
        try db.execute(sql: "DELETE FROM context_links")
        try db.execute(sql: "DELETE FROM property_definitions")
        try db.execute(sql: "DELETE FROM pages")
        try db.execute(sql: "DELETE FROM page_sets")
        try db.execute(sql: "DELETE FROM agenda_tasks")
        try db.execute(sql: "DELETE FROM agenda_events")
        try db.execute(sql: "DELETE FROM contexts")
        try db.execute(sql: "DELETE FROM page_collections")
    }

    private nonisolated static func insertPageCollections(_ db: Database, snapshot: NexusSnapshot) {
        for pt in snapshot.pageCollections {
            // Parent must land before its children; if it can't (e.g. a duplicate
            // id), skip the whole subtree — the children would only FK-fail.
            guard
                attemptInsert(
                    "page_collection \(pt.title) [\(pt.id)]",
                    {
                        try db.execute(
                            literal: """
                                INSERT INTO page_collections (id, title, icon, modified_at, schema_version)
                                VALUES (\(pt.id), \(pt.title), \(pt.icon), \(iso8601(pt.modifiedAt)), \(pt.schemaVersion))
                                """
                        )
                    })
            else { continue }

            insertPropertyDefinitions(
                db, properties: pt.properties,
                owningTypeID: pt.id, owningTypeKind: "page_collection")

            for set in pt.sets {
                insertPageSet(db, set: set)
            }
            for page in pt.directPages {
                insertPage(db, page: page)
            }
        }
    }

    /// Inserts a set row into `page_sets`, recursively inserting its children and pages.
    /// Uses `parent_collection_id` for depth-1 sets and `parent_set_id` for deeper ones.
    private nonisolated static func insertPageSet(_ db: Database, set: PageSetSnapshot) {
        guard
            attemptInsert(
                "page_set \(set.title) [\(set.id)]",
                {
                    try db.execute(
                        literal: """
                            INSERT INTO page_sets (id, parent_collection_id, parent_set_id, title, icon, modified_at, schema_version)
                            VALUES (\(set.id), \(set.parentCollectionID), \(set.parentSetID), \(set.title), \(set.icon), \(iso8601(set.modifiedAt)), \(set.schemaVersion))
                            """
                    )
                })
        else { return }
        for child in set.children {
            insertPageSet(db, set: child)
        }
        for page in set.pages {
            insertPage(db, page: page)
        }
    }

    private nonisolated static func insertPage(_ db: Database, page: PageSnapshot) {
        let propsJSON = (try? propertiesJSON(page.properties)) ?? "{}"
        attemptInsert(
            "page \(page.title) [\(page.id)]",
            {
                try db.execute(
                    literal: """
                        INSERT INTO pages (id, page_collection_id, page_set_id, title, icon, properties, modified_at)
                        VALUES (\(page.id), \(page.pageCollectionID), \(page.setID), \(page.title), \(page.icon), \(propsJSON), \(iso8601(page.modifiedAt)))
                        """
                )
            })
    }

    private nonisolated static func insertAgendaTasks(_ db: Database, snapshot: NexusSnapshot) {
        if let schema = snapshot.taskSchema {
            insertPropertyDefinitions(
                db, properties: schema.properties,
                owningTypeID: "agenda_tasks", owningTypeKind: "agenda_task_schema")
        }
        for task in snapshot.tasks {
            let propsJSON = (try? propertiesJSON(task.properties)) ?? "{}"
            attemptInsert(
                "agenda_task \(task.title) [\(task.id)]",
                {
                    try db.execute(
                        literal: """
                            INSERT INTO agenda_tasks (id, title, icon, due_at, properties, modified_at)
                            VALUES (\(task.id), \(task.title), \(task.icon), \(task.dueAt.map { iso8601($0) }), \(propsJSON), \(iso8601(task.modifiedAt)))
                            """
                    )
                })
        }
    }

    private nonisolated static func insertAgendaEvents(_ db: Database, snapshot: NexusSnapshot) {
        if let schema = snapshot.eventSchema {
            insertPropertyDefinitions(
                db, properties: schema.properties,
                owningTypeID: "agenda_events", owningTypeKind: "agenda_event_schema")
        }
        for event in snapshot.events {
            let propsJSON = (try? propertiesJSON(event.properties)) ?? "{}"
            attemptInsert(
                "agenda_event \(event.title) [\(event.id)]",
                {
                    try db.execute(
                        literal: """
                            INSERT INTO agenda_events (id, title, icon, start_at, end_at, properties, modified_at)
                            VALUES (\(event.id), \(event.title), \(event.icon), \(iso8601(event.startAt)), \(iso8601(event.endAt)), \(propsJSON), \(iso8601(event.modifiedAt)))
                            """
                    )
                })
        }
    }

    private nonisolated static func insertContexts(_ db: Database, snapshot: NexusSnapshot) {
        for ctx in snapshot.contexts {
            attemptInsert(
                "context tier-\(ctx.tier) \(ctx.title) [\(ctx.id)]",
                {
                    try db.execute(
                        literal: """
                            INSERT INTO contexts (id, tier, title, icon)
                            VALUES (\(ctx.id), \(ctx.tier), \(ctx.title), \(ctx.icon))
                            """
                    )
                })
        }
    }

    private nonisolated static func insertTierContextLinks(_ db: Database, snapshot: NexusSnapshot) {
        for pt in snapshot.pageCollections {
            for page in allPages(in: pt.sets) + pt.directPages {
                insertTierContextLinkRows(
                    db, sourceID: page.id, sourceKind: "page",
                    tier1: page.tier1, tier2: page.tier2, tier3: page.tier3,
                    modifiedAt: page.modifiedAt)
            }
        }
        for task in snapshot.tasks {
            insertTierContextLinkRows(
                db, sourceID: task.id, sourceKind: "agenda_task",
                tier1: task.tier1, tier2: task.tier2, tier3: task.tier3,
                modifiedAt: task.modifiedAt)
        }
        for event in snapshot.events {
            insertTierContextLinkRows(
                db, sourceID: event.id, sourceKind: "agenda_event",
                tier1: event.tier1, tier2: event.tier2, tier3: event.tier3,
                modifiedAt: event.modifiedAt)
        }
    }

    /// Recursively collects all pages from a set tree.
    private nonisolated static func allPages(in sets: [PageSetSnapshot]) -> [PageSnapshot] {
        sets.flatMap { set in set.pages + allPages(in: set.children) }
    }

    /// Emits one `context_links` row per tier value.
    /// `target_kind` derives from `RelationTargetKind.string(from: .contextTier(n))`
    /// (DRY — shared with property relations); `property_id` is the reserved tier ID.
    private nonisolated static func insertTierContextLinkRows(
        _ db: Database,
        sourceID: String,
        sourceKind: String,
        tier1: [String],
        tier2: [String],
        tier3: [String],
        modifiedAt: Date
    ) {
        let tiers: [(Int, [String], String)] = [
            (1, tier1, ReservedPropertyID.tier1),
            (2, tier2, ReservedPropertyID.tier2),
            (3, tier3, ReservedPropertyID.tier3),
        ]
        for (level, targetIDs, propertyID) in tiers {
            let targetKind = RelationTargetKind.string(from: .contextTier(level))
            for targetID in targetIDs {
                let relationID = ULID.generate()
                attemptInsert(
                    "tier-\(level) relation \(sourceKind) \(sourceID) → \(targetID)",
                    {
                        try db.execute(
                            literal: """
                                INSERT INTO context_links (id, source_id, source_kind, target_id, target_kind, property_id, modified_at)
                                VALUES (\(relationID), \(sourceID), \(sourceKind), \(targetID), \(targetKind), \(propertyID), \(iso8601(modifiedAt)))
                                """
                        )
                    })
            }
        }
    }

    /// Cold-start backfill of the `connections` table from Page bodies.
    /// Runs AFTER the entity rows are inserted so single-match title resolution
    /// can see targets. Best-effort: on a freshly-adopted nexus, a target whose
    /// type/collection wasn't indexed yet resolves as phantom and self-heals on the
    /// next CRUD write or loadAll (quirk #10). Each row is resilient via attemptInsert.
    private nonisolated static func insertConnections(_ db: Database, snapshot: NexusSnapshot) {
        func emit(sourceID: String, sourceTitle: String, body: String) {
            let selfKey = ConnectionTitle.normalize(sourceTitle)
            for c in ConnectionScanner.scan(body: body) {
                if c.normalizedTitle == selfKey { continue }
                let matches = (try? String.fetchAll(
                    db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE",
                    arguments: [c.normalizedTitle])) ?? []
                let targetID: String? = matches.count == 1 ? matches[0] : nil
                attemptInsert("connection page \(sourceID) → \(c.normalizedTitle)") {
                    try db.execute(
                        sql: """
                            INSERT INTO connections
                                (id, source_id, source_kind, target_id, target_kind, target_title,
                                 surface, multiplicity, weight, resolved, modified_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1.0, ?, ?)
                            """,
                        arguments: [UUID().uuidString, sourceID, "page", targetID, "page",
                                    c.normalizedTitle, "page_body", c.multiplicity, targetID != nil ? 1 : 0, iso8601(Date())])
                }
            }
        }
        for pt in snapshot.pageCollections {
            for p in allPages(in: pt.sets) + pt.directPages {
                emit(sourceID: p.id, sourceTitle: p.title, body: p.body)
            }
        }
    }

    private nonisolated static func insertPropertyDefinitions(
        _ db: Database,
        properties: [PropertyDefinition],
        owningTypeID: String,
        owningTypeKind: String
    ) {
        for (position, def) in properties.enumerated() {
            guard !def.id.isEmpty else { continue }
            let configJSON = (try? definitionConfigJSON(def)) ?? "{}"
            let modAt = iso8601(Date())
            attemptInsert(
                "property_definition \(def.name) [\(def.id)] on \(owningTypeKind) \(owningTypeID)",
                {
                    try db.execute(
                        literal: """
                            INSERT INTO property_definitions
                                (id, owning_type_id, owning_type_kind, name, type, config, position, modified_at)
                            VALUES (\(def.id), \(owningTypeID), \(owningTypeKind), \(def.name), \(def.type.rawValue), \(configJSON), \(position), \(modAt))
                            """
                    )
                })
        }
    }

    // MARK: - Encoding helpers (nonisolated — pure computation, no domain-type calls)

    private nonisolated static func iso8601(_ date: Date) -> String {
        IndexDateFormat.iso8601.string(from: date)
    }

    private nonisolated static func propertiesJSON(_ properties: [String: PropertyValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(properties)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private nonisolated static func definitionConfigJSON(_ def: PropertyDefinition) throws -> String {
        // Single source of truth for the `property_definitions.config` blob —
        // shared with `IndexUpdater` so both paths write the same shape.
        def.indexConfigJSON()
    }
}
