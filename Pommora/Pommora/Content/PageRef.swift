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
}

extension PageRef {
    /// Resolve to live PageMeta + Vault + Collection via the running managers.
    /// Returns `nil` if any link in the chain is missing — e.g., the Vault was
    /// deleted while a standalone window was minimized, or the Page was moved
    /// across Vaults.
    @MainActor
    func resolve(
        vaultManager: PageTypeManager,
        contentManager: ContentManager
    ) -> (page: PageMeta, vault: PageType, collection: PageCollection?)? {
        guard let vault = vaultManager.types.first(where: { $0.id == vaultID }) else {
            return nil
        }
        if let collectionID {
            guard
                let collection = vaultManager.pageCollections(in: vault)
                    .first(where: { $0.id == collectionID }),
                let page = contentManager.pages(in: collection)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, vault, collection)
        } else {
            guard
                let page = contentManager.pages(in: vault)
                    .first(where: { $0.id == pageID })
            else { return nil }
            return (page, vault, nil)
        }
    }

    /// Construct a PageRef from a resolved PageMeta + its parent Vault/PageCollection.
    init(page: PageMeta, in collection: PageCollection, vault: PageType) {
        self.pageID = page.id
        self.vaultID = vault.id
        self.collectionID = collection.id
    }

    /// Construct a PageRef for a vault-root Page (no Collection parent).
    init(page: PageMeta, inVaultRoot vault: PageType) {
        self.pageID = page.id
        self.vaultID = vault.id
        self.collectionID = nil
    }
}
