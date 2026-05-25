import Foundation
import GRDB

/// Notion-style query API over the SQLite index. Pure read surface — never
/// writes. Backs relation picker, sort, filter, broken-links surfaces.
struct IndexQuery: Sendable {
    let index: PommoraIndex

    init(_ index: PommoraIndex) { self.index = index }

    // MARK: - Scope queries

    /// Returns all entities matching a scope (Page Type, Item Type, etc.).
    func entitiesByScope(_ scope: PropertyDefinition.RelationScope) async throws -> [EntityRef] {
        try await index.dbQueue.read { db in
            switch scope {
            case .pageType(let id):
                return try Row.fetchAll(db, sql: "SELECT id, title FROM pages WHERE page_type_id = ?", arguments: [id])
                    .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"]) }

            case .itemType(let id):
                return try Row.fetchAll(db, sql: "SELECT id, title FROM items WHERE item_type_id = ?", arguments: [id])
                    .map { EntityRef(id: $0["id"], kind: .item, title: $0["title"]) }

            case .pageCollection(let id):
                return try Row.fetchAll(db, sql: "SELECT id, title FROM pages WHERE page_collection_id = ?", arguments: [id])
                    .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"]) }

            case .itemCollection(let id):
                return try Row.fetchAll(db, sql: "SELECT id, title FROM items WHERE item_collection_id = ?", arguments: [id])
                    .map { EntityRef(id: $0["id"], kind: .item, title: $0["title"]) }

            case .contextTier(let tier):
                return try Row.fetchAll(db, sql: "SELECT id, title, tier FROM contexts WHERE tier = ?", arguments: [tier])
                    .map { row -> EntityRef in
                        let t = (row["tier"] as Int?) ?? tier
                        let kind: EntityKind = t == 1 ? .space : (t == 2 ? .topic : .project)
                        return EntityRef(id: row["id"], kind: kind, title: row["title"])
                    }
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
            let sourceRows = try Row.fetchAll(db,
                sql: "SELECT id, name FROM property_definitions WHERE owning_type_id = ? AND owning_type_kind = ?",
                arguments: [sourceID, srcKindStr])
            let destNameSet = Set(try String.fetchAll(db,
                sql: "SELECT name FROM property_definitions WHERE owning_type_id = ? AND owning_type_kind = ?",
                arguments: [destTypeID, dstKindStr]))

            let stripped = sourceRows.filter { !destNameSet.contains($0["name"] as String) }
            return StripReport(
                strippedPropertyIDs: stripped.map { $0["id"] },
                strippedPropertyNames: stripped.map { $0["name"] }
            )
        }
    }

    // MARK: - Broken links

    /// Returns relations whose target_id no longer exists in the corresponding entity table.
    func brokenLinks() async throws -> [BrokenLinkReport] {
        // Inline kind conversion to avoid calling actor-isolated helpers inside @Sendable closure.
        let kindFromString: @Sendable (String) -> EntityKind = { s in
            switch s {
            case "page":            return .page
            case "item":            return .item
            case "agenda_task":     return .agendaTask
            case "agenda_event":    return .agendaEvent
            case "page_type":       return .pageType
            case "item_type":       return .itemType
            case "page_collection": return .pageCollection
            case "item_collection": return .itemCollection
            case "space":           return .space
            case "topic":           return .topic
            case "project":         return .project
            default:                return .page
            }
        }

        return try await index.dbQueue.read { db in
            let kindTableMap: [String: String] = [
                "page": "pages",
                "item": "items",
                "agenda_task": "agenda_tasks",
                "agenda_event": "agenda_events",
                "space": "contexts",
                "topic": "contexts",
                "project": "contexts",
                "pageType": "page_types",
                "itemType": "item_types",
                "pageCollection": "page_collections",
                "itemCollection": "item_collections",
            ]

            let distinctKinds = try String.fetchAll(db, sql: "SELECT DISTINCT target_kind FROM relations")

            var reports: [BrokenLinkReport] = []
            for kindStr in distinctKinds {
                guard let joinTable = kindTableMap[kindStr] else { continue }
                let sql = """
                    SELECT r.id AS relation_id,
                           r.source_id,
                           r.source_kind,
                           r.target_id,
                           r.target_kind,
                           r.property_id
                    FROM relations r
                    LEFT JOIN \(joinTable) t ON r.target_id = t.id
                    WHERE r.target_kind = ?
                      AND t.id IS NULL
                    """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [kindStr])
                for row in rows {
                    let skStr: String = row["source_kind"]
                    let tkStr: String = row["target_kind"]
                    reports.append(BrokenLinkReport(
                        relationID: row["relation_id"],
                        sourceID: row["source_id"],
                        sourceKind: kindFromString(skStr),
                        targetID: row["target_id"],
                        targetKind: kindFromString(tkStr),
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

    nonisolated static func targetSQL(_ target: TargetRef)
        -> (String, String, String, String, [any DatabaseValueConvertible])
    {
        switch target {
        case .pageType(let id):       return ("pages", "id", "title", "page_type_id = ?", [id])
        case .itemType(let id):       return ("items", "id", "title", "item_type_id = ?", [id])
        case .pageCollection(let id): return ("pages", "id", "title", "page_collection_id = ?", [id])
        case .itemCollection(let id): return ("items", "id", "title", "item_collection_id = ?", [id])
        case .agendaTasks:            return ("agenda_tasks", "id", "title", "", [])
        case .agendaEvents:           return ("agenda_events", "id", "title", "", [])
        case .contextTier(let t):     return ("contexts", "id", "title", "tier = ?", [t])
        }
    }

    nonisolated static func targetEntityKind(_ target: TargetRef) -> EntityKind {
        switch target {
        case .pageType, .pageCollection:  return .page
        case .itemType, .itemCollection:  return .item
        case .agendaTasks:                return .agendaTask
        case .agendaEvents:               return .agendaEvent
        case .contextTier(let t):         return t == 1 ? .space : (t == 2 ? .topic : .project)
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
            return ("""
                EXISTS (
                    SELECT 1 FROM json_each(json_extract(properties, '$.\(pid)'))
                    WHERE value = ?
                )
                """, innerArgs)

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
        case .number(let n):    return ("?", [n])
        case .checkbox(let b):  return ("?", [b ? 1 : 0])
        case .select(let s):    return ("?", [s])
        case .status(let s):    return ("?", [s])
        case .relation(let id): return ("?", [id])
        case .url(let u):       return ("?", [u.absoluteString])
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
        case .file, .lastEditedTime, .null:
            return ("NULL", [])
        }
    }

    // MARK: - EntityKind helpers (live here to stay nonisolated)

    nonisolated static func entityKindToOwningTypeKind(_ kind: EntityKind) -> String {
        switch kind {
        case .pageType:       return "page_type"
        case .itemType:       return "item_type"
        case .pageCollection: return "page_collection"
        case .itemCollection: return "item_collection"
        case .agendaTask:     return "agenda_task"
        case .agendaEvent:    return "agenda_event"
        case .page:           return "page"
        case .item:           return "item"
        case .space:          return "space"
        case .topic:          return "topic"
        case .project:        return "project"
        }
    }

    nonisolated static func entityKindFromString(_ s: String) -> EntityKind {
        switch s {
        case "page":            return .page
        case "item":            return .item
        case "agenda_task":     return .agendaTask
        case "agenda_event":    return .agendaEvent
        case "page_type":       return .pageType
        case "item_type":       return .itemType
        case "page_collection": return .pageCollection
        case "item_collection": return .itemCollection
        case "space":           return .space
        case "topic":           return .topic
        case "project":         return .project
        default:                return .page
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

enum SortDirection: String, Sendable { case ascending, descending }

enum EntityKind: String, Codable, Sendable {
    case page, item, agendaTask, agendaEvent, pageType, itemType,
         pageCollection, itemCollection, space, topic, project
}

struct EntityRef: Equatable, Hashable, Sendable {
    let id: String
    let kind: EntityKind
    let title: String
}

enum TargetRef: Sendable {
    case pageType(String)
    case itemType(String)
    case pageCollection(String)
    case itemCollection(String)
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
