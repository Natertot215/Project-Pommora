import Foundation

/// Comparison operators a `FilterRule` may carry. Serialized as the rule's `op`
/// raw string. The per-type matrix in `FilterEvaluator` decides which ops are
/// meaningful for a given property type; an op outside a type's matrix is a
/// no-op (the rule passes — a filter never excludes on an operator it can't apply).
enum FilterOperator: String, Codable, CaseIterable, Sendable {
    case isEqual = "is"
    case isNot = "is_not"
    case contains
    case doesNotContain = "does_not_contain"
    case isEmpty = "is_empty"
    case isNotEmpty = "is_not_empty"
    case greaterThan = "greater_than"
    case lessThan = "less_than"
    case onOrAfter = "on_or_after"
    case onOrBefore = "on_or_before"
}

/// Pure filter engine. Applies a `FilterGroup` (flat rules + `MatchMode`) against
/// a page's frontmatter. No disk, no SwiftUI. `schema` supplies property types so
/// the per-type operator matrix can resolve.
///
/// Unknown / absent operator = rule no-op (rule PASSES — never excludes). The same
/// holds when a rule names a property absent from the schema: it can't be evaluated,
/// so it passes. `MatchMode.all` = AND, `.any` = OR.
enum FilterEvaluator {
    static func matches(
        _ fm: PageFrontmatter,
        group: FilterGroup,
        schema: [PropertyDefinition]
    ) -> Bool {
        // No rules → everything matches (an empty filter is the identity).
        guard !group.rules.isEmpty else { return true }

        let results = group.rules.map { evaluate($0, fm: fm, schema: schema) }
        switch group.match {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains(true)
        }
    }

    // MARK: - Single-rule evaluation

    private static func evaluate(
        _ rule: FilterRule,
        fm: PageFrontmatter,
        schema: [PropertyDefinition]
    ) -> Bool {
        // Unknown operator → no-op pass.
        guard let op = FilterOperator(rawValue: rule.op) else { return true }

        // Tier rules read the frontmatter tier arrays; user-property rules read
        // `fm.properties`. Tier rules support the membership/presence operators.
        if let tier = ReservedPropertyID.tierNumber(forID: rule.propertyID) {
            let ids = tierIDs(fm, tier: tier)
            return evaluateList(ids, op: op, value: rule.value)
        }

        // The reserved "Last edited" column resolves its date from the dedicated
        // `modifiedAt` stamp (with `createdAt` fallback), NOT from `fm.properties`
        // — it's never a stored property key (mirrors `ViewSortComparator`'s
        // modified-stamp handling). Route it straight through the date matrix.
        if rule.propertyID == ReservedPropertyID.modifiedAt {
            return evaluateDate(
                .date(fm.modifiedAt ?? fm.createdAt), op: op, expected: rule.value)
        }

        // A rule for a property the schema doesn't know about can't be evaluated
        // meaningfully → no-op pass.
        guard let def = schema.first(where: { $0.id == rule.propertyID }) else { return true }
        let value = fm.properties[rule.propertyID]
        return evaluate(value: value, op: op, expected: rule.value, type: def.type)
    }

    private static func tierIDs(_ fm: PageFrontmatter, tier: Int) -> [String] {
        switch tier {
        case 1: return fm.tier1
        case 2: return fm.tier2
        default: return fm.tier3
        }
    }

    /// Tier (and any multi-id list) operators: presence + membership only.
    private static func evaluateList(_ ids: [String], op: FilterOperator, value: String?) -> Bool {
        switch op {
        case .isEmpty: return ids.isEmpty
        case .isNotEmpty: return !ids.isEmpty
        case .isEqual, .contains: return value.map(ids.contains) ?? false
        case .isNot, .doesNotContain: return value.map { !ids.contains($0) } ?? true
        default: return true  // op outside the list matrix → no-op pass
        }
    }

    // MARK: - Per-type matrix

    private static func evaluate(
        value: PropertyValue?,
        op: FilterOperator,
        expected: String?,
        type: PropertyType
    ) -> Bool {
        switch type {
        case .number:
            return evaluateNumber(value, op: op, expected: expected)
        case .date, .datetime, .lastEditedTime:
            return evaluateDate(value, op: op, expected: expected)
        case .checkbox:
            return evaluateCheckbox(value, op: op, expected: expected)
        case .select, .status, .url:
            return evaluateText(value, op: op, expected: expected)
        case .multiSelect:
            return evaluateMulti(value, op: op, expected: expected)
        case .relation, .file:
            // Presence-only for these; equality/contains not modeled here.
            return evaluatePresence(value, op: op)
        }
    }

    // MARK: - Per-type evaluators

    private static func evaluateNumber(
        _ value: PropertyValue?, op: FilterOperator, expected: String?
    ) -> Bool {
        let n: Double? = {
            if case .number(let x) = value { return x }
            return nil
        }()
        switch op {
        case .isEmpty: return n == nil
        case .isNotEmpty: return n != nil
        case .isEqual:
            guard let n, let e = expected.flatMap(Double.init) else { return true }
            return n == e
        case .isNot:
            guard let n, let e = expected.flatMap(Double.init) else { return true }
            return n != e
        case .greaterThan:
            guard let n, let e = expected.flatMap(Double.init) else { return true }
            return n > e
        case .lessThan:
            guard let n, let e = expected.flatMap(Double.init) else { return true }
            return n < e
        default: return true  // op outside number matrix → no-op pass
        }
    }

    private static func evaluateDate(
        _ value: PropertyValue?, op: FilterOperator, expected: String?
    ) -> Bool {
        let d: Date? = {
            switch value {
            case .date(let x), .datetime(let x): return x
            default: return nil
            }
        }()
        switch op {
        case .isEmpty: return d == nil
        case .isNotEmpty: return d != nil
        case .onOrAfter:
            guard let d, let e = parseDate(expected) else { return true }
            return d >= e
        case .onOrBefore:
            guard let d, let e = parseDate(expected) else { return true }
            return d <= e
        default: return true  // op outside date matrix → no-op pass
        }
    }

    private static func evaluateCheckbox(
        _ value: PropertyValue?, op: FilterOperator, expected: String?
    ) -> Bool {
        let b: Bool = {
            if case .checkbox(let x) = value { return x }
            return false
        }()
        switch op {
        case .isEmpty: return value == nil || value == .null
        case .isEqual, .isNot:
            // Expected is "true"/"false"; absent expected → no-op pass.
            guard let e = expected.flatMap(parseBool) else { return true }
            return op == .isEqual ? (b == e) : (b != e)
        default: return true  // op outside checkbox matrix → no-op pass
        }
    }

    private static func evaluateText(
        _ value: PropertyValue?, op: FilterOperator, expected: String?
    ) -> Bool {
        let s = textValue(value)
        switch op {
        case .isEmpty: return s?.isEmpty ?? true
        case .isNotEmpty: return !(s?.isEmpty ?? true)
        case .isEqual:
            guard let s, let e = expected else { return true }
            return s == e
        case .isNot:
            guard let e = expected else { return true }
            return s != e
        case .contains:
            guard let s, let e = expected else { return true }
            return s.localizedCaseInsensitiveContains(e)
        case .doesNotContain:
            guard let e = expected else { return true }
            return !(s?.localizedCaseInsensitiveContains(e) ?? false)
        default: return true  // op outside text matrix → no-op pass
        }
    }

    private static func evaluateMulti(
        _ value: PropertyValue?, op: FilterOperator, expected: String?
    ) -> Bool {
        let xs: [String] = {
            if case .multiSelect(let a) = value { return a }
            return []
        }()
        switch op {
        case .isEmpty: return xs.isEmpty
        case .isNotEmpty: return !xs.isEmpty
        case .isEqual, .contains: return expected.map(xs.contains) ?? true
        case .isNot, .doesNotContain: return expected.map { !xs.contains($0) } ?? true
        default: return true  // op outside multi matrix → no-op pass
        }
    }

    private static func evaluatePresence(_ value: PropertyValue?, op: FilterOperator) -> Bool {
        let isEmpty: Bool = {
            switch value {
            case .none, .some(.null): return true
            case .some(.relation(let ids)): return ids.isEmpty
            case .some(.file(let refs)): return refs.isEmpty
            default: return false
            }
        }()
        switch op {
        case .isEmpty: return isEmpty
        case .isNotEmpty: return !isEmpty
        default: return true  // op outside presence matrix → no-op pass
        }
    }

    // MARK: - Value extraction helpers

    /// The comparable text form of a single-valued property (select/status/url).
    private static func textValue(_ value: PropertyValue?) -> String? {
        switch value {
        case .select(let s), .status(let s): return s
        case .url(let u): return u.absoluteString
        case .none, .some(.null): return nil
        default: return nil
        }
    }

    private static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    /// Parses an expected date filter operand — full ISO-8601 first, then yyyy-MM-dd.
    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: s)
    }
}
