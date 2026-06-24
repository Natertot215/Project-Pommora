import Foundation

/// Where a Page lives inside a Page Type. The spec allows Content to sit
/// directly in a Page Type's root folder, inside a PageSet sub-folder,
/// OR inside a PageSet sub-folder of a PageSet; this enum lets sidebar
/// rows and sheets route create/rename/delete calls to the correct
/// ContentManager overload without leaking that branching into UI code.
enum PageParent: Hashable {
    case collection(PageSet, pageCollection: PageCollection)
    case set(PageSet, collection: PageSet, pageCollection: PageCollection)
    case collectionRoot(PageCollection)
}

extension PageParent {
    /// The owning Page Type — every case carries it.
    var pageCollection: PageCollection {
        switch self {
        case .collection(_, let vault): return vault
        case .set(_, _, let vault): return vault
        case .collectionRoot(let vault): return vault
        }
    }

    /// The enclosing PageSet's id, nil at the collection root.
    var collectionID: String? {
        switch self {
        case .collection(let coll, _): return coll.id
        case .set(_, let coll, _): return coll.id
        case .collectionRoot: return nil
        }
    }

    /// The enclosing PageSet's id, nil outside a Set.
    var setID: String? {
        switch self {
        case .set(let set, _, _): return set.id
        case .collection, .collectionRoot: return nil
        }
    }

    /// The enclosing PageSet, nil outside a Set.
    var set: PageSet? {
        switch self {
        case .set(let set, _, _): return set
        case .collection, .collectionRoot: return nil
        }
    }

    /// The enclosing PageSet, nil at the collection root.
    var collection: PageSet? {
        switch self {
        case .collection(let coll, _): return coll
        case .set(_, let coll, _): return coll
        case .collectionRoot: return nil
        }
    }

    /// Persisted display order for direct child Pages at this location.
    var pageOrder: [String]? {
        switch self {
        case .collection(let coll, _): return coll.pageOrder
        case .set(let set, _, _): return set.pageOrder
        case .collectionRoot(let vault): return vault.pageOrder
        }
    }
}
