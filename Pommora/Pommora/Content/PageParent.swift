import Foundation

/// Where a Page lives inside a Page Type. The spec allows Content to sit
/// directly in a Page Type's root folder, inside a PageCollection sub-folder,
/// OR inside a PageSet sub-folder of a PageCollection; this enum lets sidebar
/// rows and sheets route create/rename/delete calls to the correct
/// ContentManager overload without leaking that branching into UI code.
enum PageParent: Hashable {
    case collection(PageCollection, vault: PageType)
    case set(PageSet, collection: PageCollection, vault: PageType)
    case vaultRoot(PageType)
}

extension PageParent {
    /// The owning Page Type — every case carries it.
    var vault: PageType {
        switch self {
        case .collection(_, let vault): return vault
        case .set(_, _, let vault): return vault
        case .vaultRoot(let vault): return vault
        }
    }

    /// The enclosing PageCollection's id, nil at the vault root.
    var collectionID: String? {
        switch self {
        case .collection(let coll, _): return coll.id
        case .set(_, let coll, _): return coll.id
        case .vaultRoot: return nil
        }
    }

    /// The enclosing PageSet's id, nil outside a Set.
    var setID: String? {
        switch self {
        case .set(let set, _, _): return set.id
        case .collection, .vaultRoot: return nil
        }
    }

    /// The enclosing PageSet, nil outside a Set.
    var set: PageSet? {
        switch self {
        case .set(let set, _, _): return set
        case .collection, .vaultRoot: return nil
        }
    }

    /// The enclosing PageCollection, nil at the vault root.
    var collection: PageCollection? {
        switch self {
        case .collection(let coll, _): return coll
        case .set(_, let coll, _): return coll
        case .vaultRoot: return nil
        }
    }

    /// Persisted display order for direct child Pages at this location.
    var pageOrder: [String]? {
        switch self {
        case .collection(let coll, _): return coll.pageOrder
        case .set(let set, _, _): return set.pageOrder
        case .vaultRoot(let vault): return vault.pageOrder
        }
    }
}
