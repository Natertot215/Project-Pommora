import Foundation

/// Pure sort engine. Builds a group-sorter `([ViewItem]) -> [ViewItem]` from a
/// `SortCriterion` against a property schema, or returns `nil` for manual order
/// (caller preserves input order). Decorate-sort: each item's sort key is
/// extracted ONCE, then compared — no per-comparison re-extraction. No disk, no
/// SwiftUI.
///
/// Reserved criteria:
///   - `_title`        — case-insensitive filename compare.
///   - `_id`           — lexicographic ULID compare (= creation order).
///   - `_modified_at`  — `modifiedAt` with `createdAt` fallback when nil.
/// Select / status properties sort BY SCHEMA OPTION ORDER (not alphabetic).
/// `SortDirection` is honored (descending flips the comparison); ties hold input
/// order in both directions via a stable offset tiebreak.
enum ViewSortComparator {
    /// Orders a group's items. `nil` = manual order (no criterion / unknown
    /// property) — caller keeps input order.
    typealias GroupSorter = ([ViewItem]) -> [ViewItem]

    static func sorter(
        for criterion: SortCriterion?,
        schema: [PropertyDefinition]
    ) -> GroupSorter? {
        guard let criterion else { return nil }
        let ascending = criterion.direction == .ascending

        switch criterion.propertyID {
        case ReservedPropertyID.title:
            return decorator(ascending: ascending, key: { $0.page.title }, less: caseInsensitiveLess)
        case ReservedPropertyID.id:
            return decorator(ascending: ascending, key: { $0.page.id }, less: { $0 < $1 })
        case ReservedPropertyID.modifiedAt:
            return decorator(
                ascending: ascending, key: { modifiedStamp($0.page.frontmatter) }, less: { $0 < $1 })
        default:
            return propertySorter(criterion.propertyID, schema: schema, ascending: ascending)
        }
    }

    // MARK: - Property sorters

    private static func propertySorter(
        _ propertyID: String,
        schema: [PropertyDefinition],
        ascending: Bool
    ) -> GroupSorter? {
        guard let def = schema.first(where: { $0.id == propertyID }) else { return nil }

        switch def.type {
        case .select, .status:
            let order = optionOrderIndex(def)
            return decorator(ascending: ascending, key: { rank($0, propertyID, order) }, less: { $0 < $1 })
        case .number:
            return decorator(ascending: ascending, key: { numberOf($0, propertyID) }, less: { $0 < $1 })
        case .date, .datetime, .lastEditedTime:
            return decorator(ascending: ascending, key: { dateOf($0, propertyID) }, less: { $0 < $1 })
        case .checkbox:
            // false < true
            return decorator(ascending: ascending, key: { boolOf($0, propertyID) }, less: { !$0 && $1 })
        case .url, .multiSelect, .relation, .file:
            return decorator(ascending: ascending, key: { sortText($0, propertyID) }, less: caseInsensitiveLess)
        }
    }

    // MARK: - Decorate-sort

    /// Stable group-sorter: extracts each item's sort key once, then orders by
    /// `less` (flipped for descending), holding input order among ties.
    private static func decorator<K>(
        ascending: Bool,
        key: @escaping (ViewItem) -> K,
        less: @escaping (K, K) -> Bool
    ) -> GroupSorter {
        { items in
            items.enumerated()
                .map { (offset: $0.offset, key: key($0.element), element: $0.element) }
                .sorted { lhs, rhs in
                    if ascending {
                        if less(lhs.key, rhs.key) { return true }
                        if less(rhs.key, lhs.key) { return false }
                    } else {
                        if less(rhs.key, lhs.key) { return true }
                        if less(lhs.key, rhs.key) { return false }
                    }
                    return lhs.offset < rhs.offset  // stable: input order among ties
                }
                .map(\.element)
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

    // MARK: - Key helpers

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
