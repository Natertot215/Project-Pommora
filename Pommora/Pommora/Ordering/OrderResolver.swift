import Foundation

/// Resolves the display order of a collection of entities against an optional
/// persisted-order array of IDs.
///
/// Semantics (used uniformly across SpaceManager / TopicManager / PageTypeManager /
/// ContentManager since v0.2.8.0):
///
/// - **No persisted order** (nil): items are sorted by title via
///   `localizedStandardCompare(.orderedAscending)`. This is the pre-v0.2.8
///   behavior — the resolver is a drop-in replacement that produces an
///   identical result for any nexus that has never been reordered.
///
/// - **Persisted order present**: the resolver returns
///     `known` followed by `appended`
///   where
///     - `known` = persistedOrder.compactMap { items.first(where: { $0.id == $1 }) }
///       (honors the user's curation, drops tombstones whose files no longer exist),
///     - `appended` = items not referenced in persistedOrder, sorted alphabetically.
///   This means files that appear externally (sync, another app, fresh creates
///   on an older build) land at the end without disturbing the user's deliberate
///   placement.
///
/// The resolver is idempotent: `resolve(resolve(items), persisted)` returns the
/// same array.
enum OrderResolver {
    static func resolve<T>(
        _ items: [T],
        persistedOrder: [String]?,
        titleKeyPath: KeyPath<T, String>
    ) -> [T] where T: Identifiable, T.ID == String {
        let alphabetic: (T, T) -> Bool = { lhs, rhs in
            lhs[keyPath: titleKeyPath]
                .localizedStandardCompare(rhs[keyPath: titleKeyPath]) == .orderedAscending
        }

        guard let persistedOrder, !persistedOrder.isEmpty else {
            return items.sorted(by: alphabetic)
        }

        let byID: [String: T] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let known: [T] = persistedOrder.compactMap { byID[$0] }
        let knownIDs: Set<String> = Set(known.map(\.id))
        let appended: [T] = items.filter { !knownIDs.contains($0.id) }.sorted(by: alphabetic)
        return known + appended
    }

    /// Repositions the element identified by `draggedID` to land `position` of
    /// the element identified by `overID`. Pure function — returns the original
    /// array if either ID isn't found or `draggedID == overID`.
    static func repositioning<T>(
        _ items: [T],
        draggedID: String,
        overID: String,
        position: DropPosition
    ) -> [T] where T: Identifiable, T.ID == String {
        var arr = items
        guard draggedID != overID,
            let fromIdx = arr.firstIndex(where: { $0.id == draggedID })
        else { return items }
        let dragged = arr.remove(at: fromIdx)
        guard let toIdx = arr.firstIndex(where: { $0.id == overID }) else { return items }
        let insertAt = position == .above ? toIdx : toIdx + 1
        arr.insert(dragged, at: insertAt)
        return arr
    }
}
