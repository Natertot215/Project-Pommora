import SwiftUI

/// The container a detail view renders. A `ViewSurface` renders ONE scope —
/// vault (a PageType's whole tree) or collection (one PageCollection's Sets +
/// loose pages). Everything that genuinely differs between the two detail views
/// lives here as a slot; `ViewSurface` reads `scope.<slot>` and never branches
/// on which scope it is.
///
/// Named `DetailScope` (not `ViewScope`) to avoid colliding with the existing
/// grouping-shape `ViewScope` enum in `ResolvedGroup.swift`.
///
/// Conformers are plain value structs: NO `@State`, NO `@Environment`, NO stored
/// closures. Every manager a slot needs arrives as a method parameter at call
/// time, so a scope value has no `_TaskValueModifier` KeyPath-resolution path
/// that could trap on an un-injected environment (quirk 15).
@MainActor
protocol DetailScope {

    // MARK: - Live entities (resolved by id off the @Observable manager)

    /// The live PageType supplying schema + tier columns. Vault scope: this
    /// container; collection scope: the parent vault (Collections inherit schema).
    func schemaSource(_ types: PageTypeManager) -> PageType

    /// The live container's stable id — feeds `tableIdentity`, `editView`, and
    /// the `.task` warm-up id. Vault scope: the Type id; collection scope: the
    /// live Collection id.
    func containerID(_ types: PageTypeManager) -> String

    /// The live container's banner relative path, or nil.
    func containerBanner(_ types: PageTypeManager) -> String?

    // MARK: - Header

    var headerIcon: String { get }
    var headerTitle: String { get }

    // MARK: - Rename alert

    /// The quote glyphs wrapping the renamed title in the rename alert message.
    /// Preserved per-scope verbatim: vault uses curly “ ”, collection uses
    /// straight " " (an incidental original divergence, NOT unified here).
    var renameQuotes: (open: String, close: String) { get }

    // MARK: - Pipeline scope args

    /// The source scope `ViewItemSource.items(for:)` walks.
    func itemScope(_ types: PageTypeManager) -> ViewItemScope

    /// The grouping-shape scope `GroupResolver.resolve(scope:)` branches on.
    var groupScope: ViewScope { get }

    /// Maps a structural `ResolvedGroup` to its `PageParent` for drag drops.
    func structuralParent(_ group: ResolvedGroup, _ types: PageTypeManager) -> PageParent?

    // MARK: - Cache warm-up

    /// Loads every cache the scope's table renders. Vault scope nests two levels
    /// (collections, then their sets); collection scope nests one (its sets).
    func warmCaches(content: PageContentManager, sets: PageSetManager, types: PageTypeManager) async

    // MARK: - Group (disclosure-row) menu

    /// The container actions for a structural group's menu, or nil when the group
    /// carries no container (the headerless ungrouped band, or a group kind this
    /// scope never surfaces). `ViewSurface` renders the buttons + routes intents.
    func containerActions(for group: ResolvedGroup) -> [ContainerMenuAction]?

    // MARK: - Footer

    /// The breadcrumb segments for this scope's footer. `select` navigates the
    /// sidebar (e.g. tap the vault crumb or the ghost trail page).
    func footerCrumbs(
        trailPage: PageMeta?, content: PageContentManager,
        sets: PageSetManager,
        select: @escaping (SidebarSelection) -> Void
    ) -> [FooterCrumb]

    /// The configured label for this scope's container (Collection / Set), used
    /// in the footer's "New <container>" item.
    func containerCreateLabel(_ settings: SettingsManager) -> String

    /// Creates a Page at this scope's root and reports the new id.
    func createPage(title: String, content: PageContentManager) async throws -> PageMeta

    /// Existing Page titles at this scope's root (for default-title de-dupe).
    func existingPageTitles(_ content: PageContentManager) -> [String]

    /// Creates this scope's container kind and reports the new entity's id.
    func createContainer(
        title: String, types: PageTypeManager,
        sets: PageSetManager
    ) async throws -> String

    /// Existing container titles in this scope (for default-title de-dupe).
    func existingContainerTitles(types: PageTypeManager, sets: PageSetManager) -> [String]

    // MARK: - Container delete

    /// The confirmation dialog payload for deleting `ref`. Returns nil ONLY on the
    /// cross-scope ref arm a scope never emits (a safe no-op, not a crash); whether
    /// a confirmation is actually pending is gated by `ViewSurface`'s own
    /// `deleteTarget`. Drives the shared `.confirmationDialog`.
    func deleteConfirmation(for ref: ContainerRef, settings: SettingsManager) -> DeleteConfirmation?
}

// MARK: - Shared row targets

/// What a row action (rename / delete) targets. Page rows route uniformly off
/// `item.parent.*`; container rows carry a scope-specific `ContainerRef`. Erases
/// the divergent second case the two views' private `RowTarget` enums each had.
enum RowTarget: Hashable {
    case page(ViewItem)
    case container(ContainerRef)
}

/// A container row's target — a Collection (vault scope) or a Set (collection
/// scope). The only scope-specific arm of `RowTarget`.
enum ContainerRef: Hashable {
    case collection(PageCollection)
    case set(PageSet)

    var title: String {
        switch self {
        case .collection(let coll): return coll.title
        case .set(let set): return set.title
        }
    }

    /// Display label for the rename alert ("Collection" / "Set").
    var kindLabel: String {
        switch self {
        case .collection: return "Collection"
        case .set: return "Set"
        }
    }

    /// The icon-edit sheet target for this container kind.
    var iconTarget: SidebarSheet.IconTarget {
        switch self {
        case .collection(let coll): return .pageCollection(coll)
        case .set(let set): return .pageSet(set)
        }
    }
}

// MARK: - Group menu intents

/// One action in a structural group's disclosure-row menu. `ViewSurface` renders
/// these uniformly and dispatches each intent against its own state/bindings, so
/// no scope captures `ViewSurface`.
enum ContainerMenuAction {
    /// Navigate to the container's own detail view (Collections only — Sets have
    /// no detail view).
    case open(SidebarSelection)
    case editTitle(ContainerRef)
    case editIcon(SidebarSheet.IconTarget)
    case delete(ContainerRef)
}

// MARK: - Delete confirmation payload

/// The shared confirmation dialog's contents. `single` is the vault-scope
/// Collection delete (one destructive button); `setTwoMode` is the collection-
/// scope Set delete (Set-only vs. Set-and-Pages). The shared `.confirmationDialog`
/// switches on this to render the matching buttons.
struct DeleteConfirmation {
    let title: String
    let message: String
    let mode: Mode

    enum Mode {
        /// One destructive "Delete" that deletes the container directly.
        case single(PageCollection)
        /// Two-mode Set delete — "Delete Set Only" (rehome pages) vs.
        /// "Delete Set and Pages" (destructive).
        case setTwoMode(PageSet, collection: PageCollection)
    }
}

// MARK: - Vault scope

/// Vault detail (`PageTypeDetailView`). Spans every Collection + its Sets, plus
/// the Type's root pages.
struct VaultScope: DetailScope {
    let pageType: PageType

    func schemaSource(_ types: PageTypeManager) -> PageType {
        types.types.first { $0.id == pageType.id } ?? pageType
    }

    func containerID(_ types: PageTypeManager) -> String {
        schemaSource(types).id
    }

    func containerBanner(_ types: PageTypeManager) -> String? {
        schemaSource(types).banner
    }

    var headerIcon: String { pageType.icon ?? "tray.2" }
    var headerTitle: String { pageType.title }

    // Vault uses curly quotes (preserved verbatim).
    var renameQuotes: (open: String, close: String) { ("\u{201C}", "\u{201D}") }

    func itemScope(_ types: PageTypeManager) -> ViewItemScope {
        .vault(schemaSource(types))
    }

    var groupScope: ViewScope { .vault }

    func structuralParent(_ group: ResolvedGroup, _ types: PageTypeManager) -> PageParent? {
        switch group.kind {
        case .structuralCollection(let coll):
            return .collection(coll, vault: pageType)
        case .structuralSet(let set):
            guard
                let coll = types.pageCollections(in: schemaSource(types))
                    .first(where: { $0.id == set.collectionID })
            else { return nil }
            return .set(set, collection: coll, vault: pageType)
        default:
            return nil
        }
    }

    func warmCaches(content: PageContentManager, sets: PageSetManager, types: PageTypeManager) async {
        // Type-root pages + every Collection's pages + every Set's pages — vault
        // scope nests Sets under their Collection, so their caches must be warm.
        await content.loadAll(for: pageType)
        for coll in types.pageCollections(in: pageType) {
            await content.loadAll(for: coll)
            for set in sets.pageSets(in: coll) {
                await content.loadAll(for: set)
            }
        }
    }

    func containerActions(for group: ResolvedGroup) -> [ContainerMenuAction]? {
        guard case .structuralCollection(let coll) = group.kind else { return nil }
        let ref = ContainerRef.collection(coll)
        return [
            .open(.collection(coll)),
            .editTitle(ref),
            .editIcon(ref.iconTarget),
            .delete(ref),
        ]
    }

    func footerCrumbs(
        trailPage: PageMeta?, content: PageContentManager,
        sets: PageSetManager,
        select: @escaping (SidebarSelection) -> Void
    ) -> [FooterCrumb] {
        var crumbs: [FooterCrumb] = [FooterCrumb(title: pageType.title)]
        if let trail = trailPage,
            content.pages(in: pageType).contains(where: { $0.id == trail.id })
        {
            crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { select(.page(trail)) })
        }
        return crumbs
    }

    func containerCreateLabel(_ settings: SettingsManager) -> String {
        settings.settings.labels.pageCollection.singular
    }

    func createPage(title: String, content: PageContentManager) async throws -> PageMeta {
        try await content.createPage(name: title, inVaultRoot: pageType)
    }

    func existingPageTitles(_ content: PageContentManager) -> [String] {
        content.pages(in: pageType).map(\.title)
    }

    func createContainer(
        title: String, types: PageTypeManager,
        sets: PageSetManager
    ) async throws -> String {
        try await types.createPageCollection(name: title, inPageType: pageType).id
    }

    func existingContainerTitles(types: PageTypeManager, sets: PageSetManager) -> [String] {
        types.pageCollections(in: pageType).map(\.title)
    }

    func deleteConfirmation(for ref: ContainerRef, settings: SettingsManager) -> DeleteConfirmation? {
        // Vault scope only ever deletes Collections; a Set ref is unreachable
        // (containerActions emits only Collection refs, the sole writer of
        // deleteTarget). Degrade to nil rather than crash if that ever slips —
        // assertionFailure flags it in debug, release no-ops.
        guard case .collection(let coll) = ref else {
            assertionFailure("VaultScope received a non-Collection ContainerRef")
            return nil
        }
        let label = settings.settings.labels.pageCollection.singular
        return DeleteConfirmation(
            title: "Delete \(label) \"\(coll.title)\"?",
            message: "All Pages inside will be deleted.",
            mode: .single(coll))
    }
}

// MARK: - Collection scope

/// Collection detail (`PageCollectionDetailView`). Spans one Collection's Sets +
/// its loose root pages. Inherits schema from the parent vault.
struct CollectionScope: DetailScope {
    let collection: PageCollection
    let vault: PageType

    private func liveVault(_ types: PageTypeManager) -> PageType {
        types.types.first { $0.id == vault.id } ?? vault
    }

    private func liveCollection(_ types: PageTypeManager) -> PageCollection {
        types.pageCollections(in: liveVault(types)).first { $0.id == collection.id } ?? collection
    }

    func schemaSource(_ types: PageTypeManager) -> PageType {
        liveVault(types)
    }

    func containerID(_ types: PageTypeManager) -> String {
        liveCollection(types).id
    }

    func containerBanner(_ types: PageTypeManager) -> String? {
        liveCollection(types).banner
    }

    var headerIcon: String { "folder" }
    var headerTitle: String { collection.title }

    // Collection uses straight quotes (preserved verbatim).
    var renameQuotes: (open: String, close: String) { ("\"", "\"") }

    func itemScope(_ types: PageTypeManager) -> ViewItemScope {
        .collection(liveCollection(types), vault: liveVault(types))
    }

    var groupScope: ViewScope { .collection }

    func structuralParent(_ group: ResolvedGroup, _ types: PageTypeManager) -> PageParent? {
        if case .structuralSet(let set) = group.kind {
            return .set(set, collection: collection, vault: vault)
        }
        return nil
    }

    func warmCaches(content: PageContentManager, sets: PageSetManager, types: PageTypeManager) async {
        // Root pages + every Set's pages — Set rows render with their pages as
        // disclosure children, so their caches must be warm.
        await content.loadAll(for: collection)
        for set in sets.pageSets(in: collection) {
            await content.loadAll(for: set)
        }
    }

    func containerActions(for group: ResolvedGroup) -> [ContainerMenuAction]? {
        guard case .structuralSet(let set) = group.kind else { return nil }
        let ref = ContainerRef.set(set)
        // No Open — Sets have no detail view.
        return [
            .editTitle(ref),
            .editIcon(ref.iconTarget),
            .delete(ref),
        ]
    }

    func footerCrumbs(
        trailPage: PageMeta?, content: PageContentManager,
        sets: PageSetManager,
        select: @escaping (SidebarSelection) -> Void
    ) -> [FooterCrumb] {
        var crumbs: [FooterCrumb] = [
            FooterCrumb(title: vault.title) { select(.pageType(vault)) },
            FooterCrumb(title: collection.title),
        ]
        if let trail = trailPage {
            if content.pages(in: collection).contains(where: { $0.id == trail.id }) {
                crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { select(.page(trail)) })
            } else if let set = setContaining(pageID: trail.id, content: content, sets: sets) {
                // Trail page lives in one of this collection's Sets — show the Set
                // as a non-clickable ghost segment ahead of the page crumb.
                crumbs.append(FooterCrumb(title: set.title, isGhost: true))
                crumbs.append(FooterCrumb(title: trail.title, isGhost: true) { select(.page(trail)) })
            }
        }
        return crumbs
    }

    /// The PageSet (if any) whose loaded pages include `pageID` — nil for
    /// collection-root pages. Used only by the footer trail crumb.
    private func setContaining(
        pageID: String, content: PageContentManager,
        sets: PageSetManager
    ) -> PageSet? {
        sets.pageSets(in: collection).first { set in
            content.pages(in: set).first { $0.id == pageID } != nil
        }
    }

    func containerCreateLabel(_ settings: SettingsManager) -> String {
        settings.settings.labels.pageSet.singular
    }

    func createPage(title: String, content: PageContentManager) async throws -> PageMeta {
        try await content.createPage(name: title, in: collection, vault: vault)
    }

    func existingPageTitles(_ content: PageContentManager) -> [String] {
        content.pages(in: collection).map(\.title)
    }

    func createContainer(
        title: String, types: PageTypeManager,
        sets: PageSetManager
    ) async throws -> String {
        try await sets.createPageSet(name: title, in: collection).id
    }

    func existingContainerTitles(types: PageTypeManager, sets: PageSetManager) -> [String] {
        sets.pageSets(in: collection).map(\.title)
    }

    func deleteConfirmation(for ref: ContainerRef, settings: SettingsManager) -> DeleteConfirmation? {
        // Collection scope only ever deletes Sets; a Collection ref is unreachable
        // (containerActions emits only Set refs, the sole writer of deleteTarget).
        // Degrade to nil rather than crash if that ever slips — assertionFailure
        // flags it in debug, release no-ops.
        guard case .set(let set) = ref else {
            assertionFailure("CollectionScope received a non-Set ContainerRef")
            return nil
        }
        // Literal "Set" — preserved verbatim, NOT the configured pageSet label.
        return DeleteConfirmation(
            title: "Delete Set \"\(set.title)\"?",
            message: "\"Delete Set Only\" moves its Pages up into the Collection. "
                + "\"Delete Set and Pages\" deletes everything.",
            mode: .setTwoMode(set, collection: collection))
    }
}
