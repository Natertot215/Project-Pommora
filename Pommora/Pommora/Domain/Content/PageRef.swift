import Foundation

/// Stable identifier for a Page, suitable for `WindowGroup(for: PageRef.self)`
/// scene restoration. Carries only IDs — rename-safe; window state survives
/// file renames + moves within the same Vault. PageMeta is in-memory only and
/// non-Codable, so a separate identifier is required for SwiftUI scene values.
struct PageRef: Codable, Hashable, Sendable {
    let pageID: String
    let vaultID: String
    /// `nil` = vault-root Page (directly inside the Vault folder, not in a
    /// Collection sub-folder).
    let collectionID: String?
    /// Non-nil only for a Page inside a PageSet (which always implies a
    /// non-nil `collectionID`). Optional, so pre-Set refs decode to `nil`
    /// and restored windows keep resolving.
    let setID: String?
}

extension PageRef {
    /// Resolve to live PageMeta + Vault + Collection + Set via the running
    /// managers. Returns `nil` if any link in the chain is missing — e.g.,
    /// the Vault was deleted while a standalone window was minimized, or the
    /// Page was moved across Vaults.
    @MainActor
    func resolve(
        collectionManager: PageCollectionManager,
        contentManager: PageContentManager,
        setManager: PageSetManager
    ) -> (page: PageMeta, pageCollection: PageCollection, collection: PageSet?, set: PageSet?)? {
        guard let vault = collectionManager.types.first(where: { $0.id == vaultID }) else {
            return nil
        }
        switch (collectionID, setID) {
        case (let collectionID?, let setID?):
            guard
                let collection = collectionManager.pageCollections(in: vault)
                    .first(where: { $0.id == collectionID }),
                let set = setManager.pageSets(in: collection)
                    .first(where: { $0.id == setID }),
                let page = contentManager.pages(in: set)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, vault, collection, set)
        case (let collectionID?, nil):
            guard
                let collection = collectionManager.pageCollections(in: vault)
                    .first(where: { $0.id == collectionID }),
                let page = contentManager.pages(inCollection: collection)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, vault, collection, nil)
        case (nil, _):
            // A setID without a collectionID is malformed (Sets live inside
            // Collections) — falls through to the vault-root lookup, which
            // won't find the page and resolves nil.
            guard
                let page = contentManager.pages(in: vault)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, vault, nil, nil)
        }
    }

    /// Construct a PageRef for a Page inside a PageSet.
    init(page: PageMeta, in set: PageSet, collection: PageSet, pageCollection: PageCollection) {
        self.pageID = page.id
        self.vaultID = pageCollection.id
        self.collectionID = collection.id
        self.setID = set.id
    }

    /// Construct a PageRef from a resolved PageMeta + its parent Vault/PageSet.
    init(page: PageMeta, in collection: PageSet, pageCollection: PageCollection) {
        self.pageID = page.id
        self.vaultID = pageCollection.id
        self.collectionID = collection.id
        self.setID = nil
    }

    /// Construct a PageRef for a vault-root Page (no Collection parent).
    init(page: PageMeta, inCollectionRoot pageCollection: PageCollection) {
        self.pageID = page.id
        self.vaultID = pageCollection.id
        self.collectionID = nil
        self.setID = nil
    }
}
