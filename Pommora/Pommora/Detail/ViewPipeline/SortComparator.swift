import Foundation

/// Pure sort engine. Builds a comparator `(ViewItem, ViewItem) -> Bool` from a
/// `SortCriterion` against a property schema, or returns `nil` for manual order
/// (caller preserves input order). No disk, no SwiftUI.
///
/// Reserved criteria:
///   - `_title`        — case-insensitive filename compare.
///   - `_id`           — lexicographic ULID compare (= creation order).
///   - `_modified_at`  — `modifiedAt` with `createdAt` fallback when nil.
/// Select / status properties sort BY SCHEMA OPTION ORDER (not alphabetic).
/// `SortDirection` is honored (descending flips the comparator).
enum ViewSortComparator {
    /// A pairwise less-than over `ViewItem`. Stable-sort callers pass this to a
    /// stable sort to preserve input order among equal elements.
    typealias Comparator = (ViewItem, ViewItem) -> Bool

    /// `nil` = manual order (no sort criterion / unknown property) — caller keeps
    /// input order.
    static func comparator(
        for criterion: SortCriterion?,
        schema: [PropertyDefinition]
    ) -> Comparator? {
        guard let criterion else { return nil }
        let ascending = criterion.direction == .ascending

        switch criterion.propertyID {
        case ReservedPropertyID.title:
            return direct({ caseInsensitiveLess($0.page.title, $1.page.title) }, ascending)
        case ReservedPropertyID.id:
            return direct({ $0.page.id < $1.page.id }, ascending)
        case ReservedPropertyID.modifiedAt:
            return direct(
                { lhs, rhs in
                    modifiedStamp(lhs.page.frontmatter) < modifiedStamp(rhs.page.frontmatter)
                }, ascending)
        default:
            return propertyComparator(criterion.propertyID, schema: schema, ascending: ascending)
        }
    }

    // MARK: - Property comparators

    private static func propertyComparator(
        _ propertyID: String,
        schema: [PropertyDefinition],
        ascending: Bool
    ) -> Comparator? {
        guard let def = schema.first(where: { $0.id == propertyID }) else { return nil }

        switch def.type {
        case .select, .status:
            let order = optionOrderIndex(def)
            return direct(
                { lhs, rhs in
                    rank(lhs, propertyID, order) < rank(rhs, propertyID, order)
                }, ascending)
        case .number:
            return direct(
                { lhs, rhs in
                    numberOf(lhs, propertyID) < numberOf(rhs, propertyID)
                }, ascending)
        case .date, .datetime, .lastEditedTime:
            return direct(
                { lhs, rhs in
                    dateOf(lhs, propertyID) < dateOf(rhs, propertyID)
                }, ascending)
        case .checkbox:
            return direct(
                { lhs, rhs in
                    // false < true
                    !boolOf(lhs, propertyID) && boolOf(rhs, propertyID)
                }, ascending)
        case .url, .multiSelect, .relation, .file:
            return direct(
                { lhs, rhs in
                    caseInsensitiveLess(sortText(lhs, propertyID), sortText(rhs, propertyID))
                }, ascending)
        }
    }

    /// Maps each schema option value to its position so select/status sort by the
    /// author's option order, not alphabetically. Unknown values sort to the end.
    private static func optionOrderIndex(_ def: PropertyDefinition) -> [String: Int] {
        var index: [String: Int] = [:]
        if let opts = def.selectOptions {
            for (i, o) in opts.enumerated() { index[o.value] = i }
        }
        if let groups = def.statusGroups {
            var i = index.count
            for group in groups {
                for option in group.options {
                    index[option.value] = i
                    i += 1
                }
            }
        }
        return index
    }

    // MARK: - Direction + tie helpers

    /// Wraps a base ascending less-than, flipping it for descending. Equal elements
    /// stay equal in both directions (caller relies on a stable sort to hold input
    /// order among ties).
    private static func direct(_ base: @escaping Comparator, _ ascending: Bool) -> Comparator {
        ascending ? base : { lhs, rhs in base(rhs, lhs) }
    }

    private static func caseInsensitiveLess(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    /// `modifiedAt` with `createdAt` fallback when modified is nil.
    private static func modifiedStamp(_ fm: PageFrontmatter) -> Date {
        fm.modifiedAt ?? fm.createdAt
    }

    // MARK: - Per-item value extraction

    private static func rank(_ item: ViewItem, _ id: String, _ order: [String: Int]) -> Int {
        let value = item.page.frontmatter.properties[id]
        let key: String? = {
            switch value {
            case .select(let s), .status(let s): return s
            default: return nil
            }
        }()
        // Unknown / absent values sort to the end.
        return key.flatMap { order[$0] } ?? Int.max
    }

    private static func numberOf(_ item: ViewItem, _ id: String) -> Double {
        if case .number(let n) = item.page.frontmatter.properties[id] { return n }
        return -.greatestFiniteMagnitude  // absent sorts first ascending
    }

    private static func dateOf(_ item: ViewItem, _ id: String) -> Date {
        switch item.page.frontmatter.properties[id] {
        case .date(let d), .datetime(let d): return d
        default: return .distantPast  // absent sorts first ascending
        }
    }

    private static func boolOf(_ item: ViewItem, _ id: String) -> Bool {
        if case .checkbox(let b) = item.page.frontmatter.properties[id] { return b }
        return false
    }

    private static func sortText(_ item: ViewItem, _ id: String) -> String {
        switch item.page.frontmatter.properties[id] {
        case .url(let u): return u.absoluteString
        case .select(let s), .status(let s): return s
        case .multiSelect(let xs): return xs.joined(separator: ",")
        default: return ""
        }
    }
}
