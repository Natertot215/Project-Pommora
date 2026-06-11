import Foundation
import GRDB

/// Notion-style query API over the SQLite index. Pure read surface — never
/// writes. Backs relation picker, sort, filter, broken-links surfaces.
struct IndexQuery: Sendable {
    let index: PommoraIndex

    nonisolated init(_ index: PommoraIndex) { self.index = index }

    /// Maps a stored kind string to the table holding its title row. Single
    /// source shared by `incomingContextLinks` + `brokenLinks`.
    nonisolated private static let kindTableMap: [String: String] = [
        "page": "pages",
        "agenda_task": "agenda_tasks",
        "agenda_event": "agenda_events",
        "area": "contexts",
        "topic": "contexts",
        "project": "contexts",
        // `target_kind` is stored coarse ("page" for any type/collection
        // target — see RelationTargetKind.string), so real rows resolve via
        // the keys above. These fine-grained keys stay snake_case for
        // consistency with `FilterBuilder.entityKindFromString`.
        "page_type": "page_types",
        "page_collection": "page_collections",
    ]

    // MARK: - Target queries

    /// Returns all entities matching a target. Tier-only post-Relations-redesign.
    func entitiesByContextTarget(_ target: PropertyDefinition.RelationTarget) async throws -> [EntityRef] {
        try await index.dbQueue.read { db in
            switch target {
            case .contextTier(let tier):
                return try Row.fetchAll(
                    db, sql: "SELECT id, title, icon, tier FROM contexts WHERE tier = ?", arguments: [tier]
                )
                .map { row -> EntityRef in
                    let t = (row["tier"] as Int?) ?? tier
                    let kind: EntityKind = t == 1 ? .area : (t == 2 ? .topic : .project)
                    return EntityRef(id: row["id"], kind: kind, title: row["title"], icon: row["icon"])
                }
            }
        }
    }

    // MARK: - Grouped target query (value picker)

    /// Entities flat in `rootEntities` with no groups — the picker renders flat rows.
    /// Post-Relations-redesign: only `.contextTier` survives; the per-Type
    /// grouped paths are retired.
    func entitiesByContextTargetGrouped(_ target: PropertyDefinition.RelationTarget) async throws -> GroupedEntities {
        switch target {
        case .contextTier:
            return GroupedEntities(groups: [], rootEntities: try await entitiesByContextTarget(target))
        }
    }

    // MARK: - Batch ID resolution (context-link/tier display)

    /// Batch-resolve context-link/tier target IDs to their current display (icon + title).
    /// Searches every table a relation value can point at (pages, contexts,
    /// agenda tasks/events). IDs are globally-unique ULIDs, so a hit in one table is
    /// authoritative. Missing IDs are absent from the result (caller renders the
    /// "(missing)" fallback).
    func resolveEntities(ids: [String]) async throws -> [String: EntityRef] {
        guard !ids.isEmpty else { return [:] }
        return try await index.dbQueue.read { db in
            var out: [String: EntityRef] = [:]
            let qs = databaseQuestionMarks(count: ids.count)
            // Build per-statement arguments (one fresh consuming pass each) to avoid
            // any cross-statement reuse quirk in GRDB's StatementArguments.
            func collect(_ sql: String, _ make: (Row) -> EntityRef) throws {
                for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids)) {
                    let r = make(row)
                    out[r.id] = r
                }
            }
            try collect("SELECT id, title, icon FROM pages WHERE id IN (\(qs))") {
                EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"])
            }
            try collect("SELECT id, title, icon, tier FROM contexts WHERE id IN (\(qs))") { row in
                let t = (row["tier"] as Int?) ?? 1
                let kind: EntityKind = t == 1 ? .area : (t == 2 ? .topic : .project)
                return EntityRef(id: row["id"], kind: kind, title: row["title"], icon: row["icon"])
            }
            try collect("SELECT id, title, icon FROM agenda_tasks WHERE id IN (\(qs))") {
                EntityRef(id: $0["id"], kind: .agendaTask, title: $0["title"], icon: $0["icon"])
            }
            try collect("SELECT id, title, icon FROM agenda_events WHERE id IN (\(qs))") {
                EntityRef(id: $0["id"], kind: .agendaEvent, title: $0["title"], icon: $0["icon"])
            }
            return out
        }
    }

    // MARK: - Reverse-view query

    /// Every operational entity whose `context_links` rows point AT the given target ID
    /// (the canonical reverse-view query; powers the future LinkedFromDropdown).
    ///
    /// One `EntityRef` per `context_links` row, built from `source_id` + `source_kind`.
    /// `source_kind` resolves to `EntityKind` via the same string map as
    /// `brokenLinks`; the source's current title is read by joining `source_id`
    /// to its source-kind table (mirrors how `entitiesByContextTarget` sources titles —
    /// `context_links` itself carries no title). Sources whose row is dangling (no
    /// matching entity) fall back to an empty title.
    func incomingContextLinks(targetID: String) async throws -> [EntityRef] {
        try await index.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT source_id, source_kind FROM context_links WHERE target_id = ?",
                arguments: [targetID]
            )

            return try rows.map { row -> EntityRef in
                let sourceID: String = row["source_id"]
                let sourceKindStr: String = row["source_kind"]
                let kind = FilterBuilder.entityKindFromString(sourceKindStr)
                // Resolve the current title from the source's owning table (one row per source).
                var title = ""
                if let table = Self.kindTableMap[sourceKindStr] {
                    title =
                        try String.fetchOne(
                            db,
                            sql: "SELECT title FROM \(table) WHERE id = ?",
                            arguments: [sourceID]
                        ) ?? ""
                }
                return EntityRef(id: sourceID, kind: kind, title: title)
            }
        }
    }

    // MARK: - Container lookup (Context-delete cascade)

    /// Resolves the container (Type + optional Collection) that a Page
    /// lives in, by joining the entity row to its owning-Type / -Collection rows.
    /// Returns the container **titles** (which derive the on-disk folder URL via
    /// `NexusPaths`) plus the container **IDs** (which the manager re-supplies to
    /// `IndexUpdater.upsert…` after a mutation).
    ///
    /// Backs `unlinkTier` on `PageContentManager`: that manager receives only an
    /// entity id + kind from `incomingContextLinks` (no URL), and holds no
    /// `PageTypeManager` reference, so the index is the single source of truth
    /// for an entity's container.
    ///
    /// Returns `nil` for a dangling id, an Agenda kind (Agenda files live in a flat
    /// singleton folder — the manager derives their URL from the title alone), or
    /// any non-operational kind.
    func entityContainer(id: String, kind: EntityKind) async throws -> EntityContainer? {
        try await index.dbQueue.read { db -> EntityContainer? in
            switch kind {
            case .page:
                guard
                    let row = try Row.fetchOne(
                        db,
                        sql: "SELECT title, page_type_id, page_collection_id FROM pages WHERE id = ?",
                        arguments: [id]
                    )
                else { return nil }
                let typeID: String = row["page_type_id"]
                let typeTitle = try String.fetchOne(
                    db, sql: "SELECT title FROM page_types WHERE id = ?", arguments: [typeID]
                )
                guard let typeTitle else { return nil }
                let collectionID: String? = row["page_collection_id"]
                var collectionTitle: String?
                if let collectionID {
                    collectionTitle = try String.fetchOne(
                        db, sql: "SELECT title FROM page_collections WHERE id = ?",
                        arguments: [collectionID]
                    )
                }
                return EntityContainer(
                    entityTitle: row["title"], kind: .page,
                    typeID: typeID, typeTitle: typeTitle,
                    collectionID: collectionID, collectionTitle: collectionTitle
                )

            case .agendaTask, .agendaEvent, .pageType,
                .pageCollection, .area, .topic, .project:
                return nil
            }
        }
    }

    // MARK: - Filter queries

    /// Filter entities in `target` by criteria. Composed via AND.
    func filter(_ criteria: [FilterCriterion], in target: TargetRef) async throws -> [EntityRef] {
        // Pre-compute SQL before entering the @Sendable read closure.
        let built = FilterBuilder.build(criteria: criteria, target: target)
        return try await index.dbQueue.read { db in
            try Row.fetchAll(db, sql: built.sql, arguments: built.args)
                .map { EntityRef(id: $0["id"], kind: built.kind, title: $0["title"]) }
        }
    }

    // MARK: - Sort

    func sortBy(_ propertyID: String, direction: SortDirection, in target: TargetRef) async throws -> [EntityRef] {
        let built = FilterBuilder.buildSort(propertyID: propertyID, direction: direction, target: target)
        return try await index.dbQueue.read { db in
            try Row.fetchAll(db, sql: built.sql, arguments: built.args)
                .map { EntityRef(id: $0["id"], kind: built.kind, title: $0["title"]) }
        }
    }

    // MARK: - Move-strip preview

    /// Returns the source properties whose `name` does not exist on the destination type.
    /// Move-strip matches by NAME, not ID — property IDs are globally unique
    /// per `property_definitions.id PRIMARY KEY`, so cross-type matching by ID
    /// is structurally impossible. A source property whose name appears on the
    /// destination is preserved (value migrates by name); source-only-by-name
    /// properties are stripped.
    func moveStripCount(
        sourceID: String,
        sourceKind: EntityKind,
        destTypeID: String,
        destTypeKind: EntityKind
    ) async throws -> StripReport {
        let srcKindStr = FilterBuilder.entityKindToOwningTypeKind(sourceKind)
        let dstKindStr = FilterBuilder.entityKindToOwningTypeKind(destTypeKind)

        return try await index.dbQueue.read { db in
            let sourceRows = try Row.fetchAll(
                db,
                sql: "SELECT id, name FROM property_definitions WHERE owning_type_id = ? AND owning_type_kind = ?",
                arguments: [sourceID, srcKindStr])
            let destNameSet = Set(
                try String.fetchAll(
                    db,
                    sql: "SELECT name FROM property_definitions WHERE owning_type_id = ? AND owning_type_kind = ?",
                    arguments: [destTypeID, dstKindStr]))

            let stripped = sourceRows.filter { !destNameSet.contains($0["name"] as String) }
            return StripReport(
                strippedPropertyIDs: stripped.map { $0["id"] },
                strippedPropertyNames: stripped.map { $0["name"] }
            )
        }
    }

    // MARK: - Connections

    /// Outgoing edges authored in `sourceID`'s body.
    func outgoingConnections(sourceID: String) async throws -> [ConnectionEdge] {
        try await index.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, source_id, source_kind, target_id, target_kind, target_title, multiplicity, resolved
                FROM connections WHERE source_id = ?
                """, arguments: [sourceID]).map { Self.connectionEdge(from: $0) }
        }
    }

    /// Inbound edges (backlinks) targeting `targetID` — the same rows queried in
    /// reverse. Powers the future connections panel; reads straight from the index.
    func incomingConnections(targetID: String) async throws -> [ConnectionEdge] {
        try await index.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, source_id, source_kind, target_id, target_kind, target_title, multiplicity, resolved
                FROM connections WHERE target_id = ?
                """, arguments: [targetID]).map { Self.connectionEdge(from: $0) }
        }
    }

    /// SYNCHRONOUS unique-title resolution for the editor styler (WikiLinkResolver.resolve
    /// is sync, off the async query path). Returns the unique entity id, or nil when the
    /// title resolves to 0 (phantom) or >1 (ambiguous dup) — both render unresolved.
    nonisolated func resolveUniqueTitle(_ title: String) -> String? {
        let needle = ConnectionTitle.normalize(title)
        let ids =
            (try? index.dbQueue.read { db in
                try String.fetchAll(
                    db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE", arguments: [needle])
            }) ?? []
        return ids.count == 1 ? ids[0] : nil
    }

    /// Resolves a page from either a direct entity ID OR a display title —
    /// whichever the caller has on hand. Returns the canonical ID, or nil if no
    /// unique match is found. Used by link-click navigation where the caller may
    /// receive either format depending on whether `.wikiLinkID` was stored.
    nonisolated func resolvePageByIDOrTitle(_ idOrTitle: String) -> String? {
        (try? index.dbQueue.read { db -> String? in
            // Direct ID match (fastest path — wikiLinkID stored by autocomplete selection).
            if (try? Row.fetchOne(db, sql: "SELECT 1 FROM pages WHERE id = ?", arguments: [idOrTitle])) != nil {
                return idOrTitle
            }
            // Title match fallback (manually typed links carry the display name, not an ID).
            let needle = ConnectionTitle.normalize(idOrTitle)
            let ids = (try? String.fetchAll(
                db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE", arguments: [needle])) ?? []
            return ids.count == 1 ? ids[0] : nil
        })
    }

    /// SYNC unique-entity resolution (id + icon) for the editor styler. nil for 0/many matches.
    nonisolated func resolveUniqueEntity(_ title: String) -> (id: String, icon: String?)? {
        let needle = ConnectionTitle.normalize(title)
        let rows =
            (try? index.dbQueue.read { db in
                try Row.fetchAll(
                    db, sql: "SELECT id, icon FROM pages WHERE title = ? COLLATE NOCASE", arguments: [needle])
            }) ?? []
        guard rows.count == 1, let row = rows.first else { return nil }
        return (id: row["id"], icon: row["icon"])
    }

    /// Nexus-wide page-title existence — the uniqueness check (excludes the
    /// entity being renamed).
    func titleExists(_ title: String, excludingID: String? = nil) async throws -> Bool {
        let needle = ConnectionTitle.normalize(title)
        return try await index.dbQueue.read { db in
            let ids = try String.fetchAll(
                db, sql: "SELECT id FROM pages WHERE title = ? COLLATE NOCASE", arguments: [needle])
            return ids.contains { $0 != excludingID }
        }
    }

    /// Pages whose title prefix-matches `query` (case-insensitive) —
    /// autocomplete + the dup-tolerant "choose either" picker. Returns EVERY match
    /// (two same-titled adopted entities both surface).
    func titleCandidates(matching query: String, limit: Int = 20) async throws -> [EntityRef] {
        let prefix = ConnectionTitle.normalize(query)
        return try await index.dbQueue.read { db in
            // Ranking (locked): exact title first → shortest title → A–Z. The exact
            // match keeps the prefix WHERE; the second `?` binds the normalized full
            // query for a case-insensitive equality test (1 = exact, sorted DESC to top).
            try Row.fetchAll(db, sql: """
                SELECT id, title, icon FROM pages WHERE title LIKE ?
                ORDER BY (title = ? COLLATE NOCASE) DESC, LENGTH(title) ASC, title COLLATE NOCASE ASC
                LIMIT ?
                """, arguments: [prefix + "%", prefix, limit]).map {
                EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"])
            }
        }
    }

    nonisolated private static func connectionEdge(from row: Row) -> ConnectionEdge {
        ConnectionEdge(
            id: row["id"], sourceID: row["source_id"],
            sourceKind: EntityKind(rawValue: row["source_kind"]) ?? .page,
            targetID: row["target_id"],
            targetKind: EntityKind(rawValue: row["target_kind"]) ?? .page,
            targetTitle: row["target_title"], multiplicity: row["multiplicity"],
            resolved: (row["resolved"] as Int) == 1)
    }

    // MARK: - Broken links

    /// Returns context_links whose target_id no longer exists in the corresponding entity table.
    func brokenLinks() async throws -> [BrokenLinkReport] {
        try await index.dbQueue.read { db in
            let distinctKinds = try String.fetchAll(db, sql: "SELECT DISTINCT target_kind FROM context_links")

            var reports: [BrokenLinkReport] = []
            for kindStr in distinctKinds {
                guard let joinTable = Self.kindTableMap[kindStr] else { continue }
                let sql = """
                    SELECT r.id AS context_link_id,
                           r.source_id,
                           r.source_kind,
                           r.target_id,
                           r.target_kind,
                           r.property_id
                    FROM context_links r
                    LEFT JOIN \(joinTable) t ON r.target_id = t.id
                    WHERE r.target_kind = ?
                      AND t.id IS NULL
                    """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [kindStr])
                for row in rows {
                    let skStr: String = row["source_kind"]
                    let tkStr: String = row["target_kind"]
                    reports.append(
                        BrokenLinkReport(
                            relationID: row["context_link_id"],
                            sourceID: row["source_id"],
                            sourceKind: FilterBuilder.entityKindFromString(skStr),
                            targetID: row["target_id"],
                            targetKind: FilterBuilder.entityKindFromString(tkStr),
                            propertyID: row["property_id"]
                        ))
                }
            }
            return reports
        }
    }
}

// MARK: - FilterBuilder (pure value type; all members nonisolated)

private struct BuiltQuery: Sendable {
    let sql: String
    let args: StatementArguments
    let kind: EntityKind
}

private enum FilterBuilder {

    nonisolated static func build(criteria: [FilterCriterion], target: TargetRef) -> BuiltQuery {
        let (table, idCol, titleCol, scopeWhere, scopeArgs) = targetSQL(target)
        let kind = targetEntityKind(target)

        var whereClauses: [String] = []
        var args: [any DatabaseValueConvertible] = scopeArgs

        if !scopeWhere.isEmpty { whereClauses.append(scopeWhere) }
        for criterion in criteria {
            let (clause, cArgs) = criterionSQL(criterion)
            whereClauses.append(clause)
            args.append(contentsOf: cArgs)
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        let sql = "SELECT \(idCol) AS id, \(titleCol) AS title FROM \(table) \(whereSQL)"
        return BuiltQuery(sql: sql, args: StatementArguments(args), kind: kind)
    }

    nonisolated static func buildSort(propertyID: String, direction: SortDirection, target: TargetRef) -> BuiltQuery {
        let (table, idCol, titleCol, scopeWhere, scopeArgs) = targetSQL(target)
        let kind = targetEntityKind(target)
        let dir = direction == .ascending ? "ASC" : "DESC"
        let whereSQL = scopeWhere.isEmpty ? "" : "WHERE \(scopeWhere)"
        let sql = """
            SELECT \(idCol) AS id, \(titleCol) AS title
            FROM \(table)
            \(whereSQL)
            ORDER BY json_extract(properties, '$.\(propertyID)') \(dir)
            """
        return BuiltQuery(sql: sql, args: StatementArguments(scopeArgs), kind: kind)
    }

    // MARK: - Target helpers

    nonisolated static func targetSQL(
        _ target: TargetRef
    )
        -> (String, String, String, String, [any DatabaseValueConvertible])
    {
        switch target {
        case .pageType(let id): return ("pages", "id", "title", "page_type_id = ?", [id])
        case .pageCollection(let id): return ("pages", "id", "title", "page_collection_id = ?", [id])
        case .agendaTasks: return ("agenda_tasks", "id", "title", "", [])
        case .agendaEvents: return ("agenda_events", "id", "title", "", [])
        case .contextTier(let t): return ("contexts", "id", "title", "tier = ?", [t])
        }
    }

    nonisolated static func targetEntityKind(_ target: TargetRef) -> EntityKind {
        switch target {
        case .pageType, .pageCollection: return .page
        case .agendaTasks: return .agendaTask
        case .agendaEvents: return .agendaEvent
        case .contextTier(let t): return t == 1 ? .area : (t == 2 ? .topic : .project)
        }
    }

    // MARK: - Criterion SQL

    nonisolated static func criterionSQL(_ criterion: FilterCriterion) -> (String, [any DatabaseValueConvertible]) {
        switch criterion {
        case .equals(let pid, let value):
            let (ph, args) = sqlValue(value)
            return ("json_extract(properties, '$.\(pid)') = \(ph)", args)

        case .inSet(let pid, let values):
            let phs = values.map { _ in "?" }.joined(separator: ", ")
            return ("json_extract(properties, '$.\(pid)') IN (\(phs))", values.flatMap { sqlValue($0).1 })

        case .notInSet(let pid, let values):
            let phs = values.map { _ in "?" }.joined(separator: ", ")
            return ("json_extract(properties, '$.\(pid)') NOT IN (\(phs))", values.flatMap { sqlValue($0).1 })

        case .range(let pid, let min, let max):
            var clauses: [String] = []
            var args: [any DatabaseValueConvertible] = []
            if let min {
                clauses.append("json_extract(properties, '$.\(pid)') >= ?")
                args.append(contentsOf: sqlValue(min).1)
            }
            if let max {
                clauses.append("json_extract(properties, '$.\(pid)') <= ?")
                args.append(contentsOf: sqlValue(max).1)
            }
            return clauses.isEmpty ? ("1=1", []) : (clauses.joined(separator: " AND "), args)

        case .contains(let pid, let value):
            let (_, innerArgs) = sqlValue(value)
            return (
                """
                EXISTS (
                    SELECT 1 FROM json_each(json_extract(properties, '$.\(pid)'))
                    WHERE value = ?
                )
                """, innerArgs
            )

        case .exists(let pid):
            return ("json_extract(properties, '$.\(pid)') IS NOT NULL", [])

        case .isNull(let pid):
            return ("json_extract(properties, '$.\(pid)') IS NULL", [])

        case .and(let children):
            if children.isEmpty { return ("1=1", []) }
            let parts = children.map { criterionSQL($0) }
            return ("(" + parts.map(\.0).joined(separator: " AND ") + ")", parts.flatMap(\.1))

        case .or(let children):
            if children.isEmpty { return ("1=0", []) }
            let parts = children.map { criterionSQL($0) }
            return ("(" + parts.map(\.0).joined(separator: " OR ") + ")", parts.flatMap(\.1))
        }
    }

    // MARK: - PropertyValue -> SQL scalar

    nonisolated static func sqlValue(_ value: PropertyValue) -> (String, [any DatabaseValueConvertible]) {
        switch value {
        case .number(let n): return ("?", [n])
        case .checkbox(let b): return ("?", [b ? 1 : 0])
        case .select(let s): return ("?", [s])
        case .status(let s): return ("?", [s])
        case .url(let u): return ("?", [u.absoluteString])
        case .date(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return ("?", [f.string(from: d)])
        case .datetime(let d):
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            return ("?", [iso.string(from: d)])
        case .multiSelect(let xs):
            let json = (try? String(data: JSONEncoder().encode(xs), encoding: .utf8)) ?? "[]"
            return ("?", [json])
        case .relation(let ids):
            // Relations are always-multi; mirror multiSelect and serialize the id array.
            // Edge-resolution queries hit the `context_links` table directly (one row per target),
            // not this scalar value column — this branch only feeds raw-value comparisons.
            let json = (try? String(data: JSONEncoder().encode(ids), encoding: .utf8)) ?? "[]"
            return ("?", [json])
        case .file, .lastEditedTime, .null:
            return ("NULL", [])
        }
    }

    // MARK: - EntityKind helpers (live here to stay nonisolated)

    nonisolated static func entityKindToOwningTypeKind(_ kind: EntityKind) -> String {
        switch kind {
        case .pageType: return "page_type"
        case .pageCollection: return "page_collection"
        case .agendaTask: return "agenda_task"
        case .agendaEvent: return "agenda_event"
        case .page: return "page"
        case .area: return "area"
        case .topic: return "topic"
        case .project: return "project"
        }
    }

    nonisolated static func entityKindFromString(_ s: String) -> EntityKind {
        switch s {
        case "page": return .page
        case "agenda_task": return .agendaTask
        case "agenda_event": return .agendaEvent
        case "page_type": return .pageType
        case "page_collection": return .pageCollection
        case "area": return .area
        case "topic": return .topic
        case "project": return .project
        default: return .page
        }
    }
}

// MARK: - Supporting types

enum FilterCriterion: Sendable {
    case equals(propertyID: String, value: PropertyValue)
    case inSet(propertyID: String, values: [PropertyValue])
    case notInSet(propertyID: String, values: [PropertyValue])
    case range(propertyID: String, min: PropertyValue?, max: PropertyValue?)
    case contains(propertyID: String, value: PropertyValue)  // multi-select / array membership
    case exists(propertyID: String)
    case isNull(propertyID: String)
    case and([FilterCriterion])
    case or([FilterCriterion])
}

enum SortDirection: String, Codable, Equatable, Hashable, Sendable { case ascending, descending }

enum EntityKind: String, Codable, Sendable {
    case page, agendaTask, agendaEvent, pageType,
        pageCollection, area, topic, project
}

struct EntityRef: Equatable, Hashable, Sendable {
    let id: String
    let kind: EntityKind
    let title: String
    let icon: String?
    nonisolated init(id: String, kind: EntityKind, title: String, icon: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.icon = icon
    }
}

/// A Collection/Set and its member entities, for the grouped value picker.
struct EntityGroup: Sendable, Equatable {
    let container: EntityRef
    let members: [EntityRef]
    nonisolated init(container: EntityRef, members: [EntityRef]) {
        self.container = container
        self.members = members
    }
}

/// Grouped result for the value picker: Collection/Set `groups` + `rootEntities`
/// (loose, no-collection leaves). Non-grouping scopes (tiers, agenda) return empty
/// `groups` and put everything in `rootEntities`, so the picker renders flat rows.
struct GroupedEntities: Sendable, Equatable {
    let groups: [EntityGroup]
    let rootEntities: [EntityRef]
    nonisolated init(groups: [EntityGroup], rootEntities: [EntityRef]) {
        self.groups = groups
        self.rootEntities = rootEntities
    }
}

/// The on-disk container of a Page, resolved from the index by
/// `IndexQuery.entityContainer(id:kind:)`. Titles derive the folder URL via
/// `NexusPaths`; IDs re-supply `IndexUpdater.upsert…` after a mutation.
/// `collectionTitle`/`collectionID` are `nil` for Type-root entities.
struct EntityContainer: Equatable, Sendable {
    let entityTitle: String
    let kind: EntityKind  // `.page`
    let typeID: String
    let typeTitle: String
    let collectionID: String?
    let collectionTitle: String?
}

enum TargetRef: Sendable {
    case pageType(String)
    case pageCollection(String)
    case agendaTasks
    case agendaEvents
    case contextTier(Int)
}

struct StripReport: Sendable {
    let strippedPropertyIDs: [String]
    let strippedPropertyNames: [String]  // source property names not present on destination
}

struct BrokenLinkReport: Sendable {
    let relationID: String
    let sourceID: String
    let sourceKind: EntityKind
    let targetID: String
    let targetKind: EntityKind
    let propertyID: String
}

struct ConnectionEdge: Sendable, Equatable {
    let id: String
    let sourceID: String
    let sourceKind: EntityKind
    let targetID: String?
    let targetKind: EntityKind
    let targetTitle: String
    let multiplicity: Int
    let resolved: Bool
    nonisolated init(
        id: String, sourceID: String, sourceKind: EntityKind, targetID: String?,
        targetKind: EntityKind, targetTitle: String, multiplicity: Int, resolved: Bool
    ) {
        self.id = id; self.sourceID = sourceID; self.sourceKind = sourceKind
        self.targetID = targetID; self.targetKind = targetKind; self.targetTitle = targetTitle
        self.multiplicity = multiplicity; self.resolved = resolved
    }
}
