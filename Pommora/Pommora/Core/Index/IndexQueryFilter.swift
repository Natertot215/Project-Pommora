import Foundation
import GRDB

// MARK: - FilterBuilder

struct BuiltQuery: Sendable {
    let sql: String
    let args: StatementArguments
    let kind: EntityKind
}

enum FilterBuilder {

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
        case .pageSet(let id): return ("pages", "id", "title", "page_set_id = ?", [id])
        case .agendaTasks: return ("agenda_tasks", "id", "title", "", [])
        case .agendaEvents: return ("agenda_events", "id", "title", "", [])
        case .contextTier(let t): return ("contexts", "id", "title", "tier = ?", [t])
        }
    }

    nonisolated static func targetEntityKind(_ target: TargetRef) -> EntityKind {
        switch target {
        case .pageType, .pageCollection, .pageSet: return .page
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
            return ("?", [IndexDateFormat.iso8601.string(from: d)])
        case .multiSelect(let xs):
            let json = (try? String(data: JSONEncoder().encode(xs), encoding: .utf8)) ?? "[]"
            return ("?", [json])
        case .relation(let ids):
            // Relations are always-multi; mirror multiSelect and serialize the id array.
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
        case .pageSet: return "page_set"
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
        case "page_set": return .pageSet
        case "area": return .area
        case "topic": return .topic
        case "project": return .project
        default: return .page
        }
    }
}
