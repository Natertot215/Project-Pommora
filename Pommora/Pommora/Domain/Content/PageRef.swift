import Foundation

/// Stable identifier for a Page, suitable for `WindowGroup(for: PageRef.self)`
/// scene restoration. Carries only IDs — rename-safe; window state survives
/// file renames + moves within the same Collection. PageMeta is in-memory only and
/// non-Codable, so a separate identifier is required for SwiftUI scene values.
struct PageRef: Codable, Hashable, Sendable {
    let pageID: String
    let collectionID: String
    /// `nil` = collection-root Page (directly inside the Collection folder, not in a
    /// Collection sub-folder).
    let depthOneSetID: String?
    /// Non-nil only for a Page inside a PageSet (which always implies a
    /// non-nil `depthOneSetID`). Optional, so pre-Set refs decode to `nil`
    /// and restored windows keep resolving.
    let setID: String?
}

extension PageRef {
    /// Resolve to live PageMeta + Collection + Collection + Set via the running
    /// managers. Returns `nil` if any link in the chain is missing — e.g.,
    /// the Collection was deleted while a standalone window was minimized, or the
    /// Page was moved across Collections.
    @MainActor
    func resolve(
        collectionManager: PageCollectionManager,
        contentManager: PageContentManager,
        setManager: PageSetManager
    ) -> (page: PageMeta, pageCollection: PageCollection, collection: PageSet?, set: PageSet?)? {
        guard let pageCollection = collectionManager.types.first(where: { $0.id == collectionID }) else {
            return nil
        }
        switch (depthOneSetID, setID) {
        case (let depthOneSetID?, let setID?):
            guard
                let collection = collectionManager.pageCollections(in: pageCollection)
                    .first(where: { $0.id == depthOneSetID }),
                let set = setManager.pageSets(in: collection)
                    .first(where: { $0.id == setID }),
                let page = contentManager.pages(in: set)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, pageCollection, collection, set)
        case (let depthOneSetID?, nil):
            guard
                let collection = collectionManager.pageCollections(in: pageCollection)
                    .first(where: { $0.id == depthOneSetID }),
                let page = contentManager.pages(inCollection: collection)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, pageCollection, collection, nil)
        case (nil, _):
            // A setID without a depthOneSetID is malformed (Sets live inside
            // Collections) — falls through to the collection-root lookup, which
            // won't find the page and resolves nil.
            guard
                let page = contentManager.pages(in: pageCollection)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, pageCollection, nil, nil)
        }
    }

    /// Construct a PageRef for a Page inside a PageSet.
    init(page: PageMeta, in set: PageSet, collection: PageSet, pageCollection: PageCollection) {
        self.pageID = page.id
        self.collectionID = pageCollection.id
        self.depthOneSetID = collection.id
        self.setID = set.id
    }

    /// Construct a PageRef from a resolved PageMeta + its parent Collection/PageSet.
    init(page: PageMeta, in collection: PageSet, pageCollection: PageCollection) {
        self.pageID = page.id
        self.collectionID = pageCollection.id
        self.depthOneSetID = collection.id
        self.setID = nil
    }

    /// Construct a PageRef for a collection-root Page (no Collection parent).
    init(page: PageMeta, inCollectionRoot pageCollection: PageCollection) {
        self.pageID = page.id
        self.collectionID = pageCollection.id
        self.depthOneSetID = nil
        self.setID = nil
    }
}
