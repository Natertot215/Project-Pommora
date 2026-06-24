import Foundation

/// Resolves the display order of a collection of entities against an optional
/// persisted-order array of IDs.
///
/// Semantics (used uniformly across AreaManager / TopicManager / PageCollectionManager /
/// ContentManager since v0.2.8.0):
///
/// - **No persisted order** (nil or empty): items are sorted by ULID id ascending,
///   which equals creation order oldest-first. ULIDs are lexicographically sortable
///   by creation time (Crockford base32), so `$0.id < $1.id` is portable and
///   requires no `createdAt` field.
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
        // titleKeyPath is retained for source-compatibility — callers still pass it;
        // it is used only by the persisted-order appended-tail sort below.
        // Removing it from the signature (and ~20 call sites) is deferred cleanup.
        titleKeyPath: KeyPath<T, String>
    ) -> [T] where T: Identifiable, T.ID == String {
        guard let persistedOrder, !persistedOrder.isEmpty else {
            // ULID ids are lexicographically sortable by creation time → oldest first.
            return items.sorted { $0.id < $1.id }
        }

        let alphabetic: (T, T) -> Bool = { lhs, rhs in
            lhs[keyPath: titleKeyPath]
                .localizedStandardCompare(rhs[keyPath: titleKeyPath]) == .orderedAscending
        }
        let byID: [String: T] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let known: [T] = persistedOrder.compactMap { byID[$0] }
        let knownIDs: Set<String> = Set(known.map(\.id))
        let appended: [T] = items.filter { !knownIDs.contains($0.id) }.sorted(by: alphabetic)
        return known + appended
    }
}
