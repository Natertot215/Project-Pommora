import Foundation

/// The scope a `ViewItemSource` reads in. Distinct from `ViewScope`
/// (`ResolvedGroup.swift`, the grouping-shape enum) — this one carries the live
/// container values the source needs to walk the caches and stamp parents.
enum ViewItemScope {
    case vault(PageType)
    case collection(PageSet, vault: PageType)
}

/// Builds the `[ViewItem]` currency the custom table + gallery consume, reading
/// the `@Observable` page caches (already `OrderResolver`-resolved = manual
/// order) and stamping each page's structural `PageParent` + vault-scope
/// `setLabel`. Pure of grouping/filtering/sorting (downstream pipeline) — its
/// only job is fetch + parent stamping.
///
/// Vault scope: type-root pages + every collection's loose pages + every set's
/// pages. Collection scope: that collection's root pages + every set's pages.
@MainActor
enum ViewItemSource {
    static func items(
        for scope: ViewItemScope,
        content: PageContentManager,
        sets: PageSetManager,
        collections: (PageType) -> [PageSet]
    ) -> [ViewItem] {
        switch scope {
        case .vault(let vault):
            return vaultItems(vault, content: content, sets: sets, collections: collections)
        case .collection(let collection, let vault):
            return collectionItems(collection, vault: vault, content: content, sets: sets)
        }
    }

    // MARK: - Vault scope

    private static func vaultItems(
        _ vault: PageType,
        content: PageContentManager,
        sets: PageSetManager,
        collections: (PageType) -> [PageSet]
    ) -> [ViewItem] {
        var items: [ViewItem] = []

        // Type-root pages — no collection, no set, no chip label.
        items += content.pages(in: vault).map { page in
            ViewItem(page: page, parent: .vaultRoot(vault), setLabel: nil)
        }

        // Each collection: its loose pages, then each of its sets' pages.
        for collection in collections(vault) {
            items += content.pages(inCollection: collection).map { page in
                ViewItem(
                    page: page,
                    parent: .collection(collection, vault: vault),
                    setLabel: nil
                )
            }
            for set in sets.pageSets(in: collection) {
                items += content.pages(in: set).map { page in
                    ViewItem(
                        page: page,
                        parent: .set(set, collection: collection, vault: vault),
                        setLabel: set.title
                    )
                }
            }
        }
        return items
    }

    // MARK: - Collection scope

    private static func collectionItems(
        _ collection: PageSet,
        vault: PageType,
        content: PageContentManager,
        sets: PageSetManager
    ) -> [ViewItem] {
        var items: [ViewItem] = []

        // Collection-root (loose) pages.
        items += content.pages(inCollection: collection).map { page in
            ViewItem(
                page: page,
                parent: .collection(collection, vault: vault),
                setLabel: nil
            )
        }

        // Recurse through all Sets at any depth; each page carries the immediate
        // parent Set (used by GroupResolver to reconstruct the nesting).
        appendSetItems(
            from: sets.pageSets(in: collection),
            collection: collection, vault: vault,
            content: content, sets: sets, into: &items
        )
        return items
    }

    /// Appends pages for `children` and all their descendants, stamping each
    /// page's parent as its immediate set (so GroupResolver can tree-walk).
    /// For sets with no direct pages but child sub-sets, emits a structural-anchor
    /// item so GroupResolver can build the full nested tree.
    private static func appendSetItems(
        from children: [PageSet],
        collection: PageSet,
        vault: PageType,
        content: PageContentManager,
        sets: PageSetManager,
        into items: inout [ViewItem]
    ) {
        for set in children {
            let pages = content.pages(in: set)
            let childSets = sets.pageSets(in: set)
            if pages.isEmpty && !childSets.isEmpty {
                items.append(structuralAnchor(for: set, collection: collection, vault: vault))
            } else {
                items += pages.map { page in
                    ViewItem(
                        page: page,
                        parent: .set(set, collection: collection, vault: vault),
                        setLabel: nil
                    )
                }
            }
            appendSetItems(
                from: childSets,
                collection: collection, vault: vault,
                content: content, sets: sets, into: &items
            )
        }
    }

    /// Synthesizes a structural-anchor ViewItem for an empty intermediate Set.
    /// The anchor has a unique id derived from the Set's id so it can't collide
    /// with real pages. GroupResolver skips it from rendered items but uses its
    /// parent to register the Set in the tree.
    private static func structuralAnchor(
        for set: PageSet, collection: PageSet, vault: PageType
    ) -> ViewItem {
        let phantomID = "_anchor_\(set.id)"
        let meta = PageMeta(
            id: phantomID, title: "",
            url: URL(fileURLWithPath: "/"),
            frontmatter: PageFrontmatter(
                id: phantomID, icon: nil,
                tier1: [], tier2: [], tier3: [],
                properties: [:], createdAt: Date(timeIntervalSince1970: 0)
            )
        )
        return ViewItem(
            page: meta,
            parent: .set(set, collection: collection, vault: vault),
            setLabel: nil,
            isStructuralAnchor: true
        )
    }
}
