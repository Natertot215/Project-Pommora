import Foundation

/// Resolves a clicked `[[Title]]` to a navigable page selection. Reuses the index
/// (resolveUniqueTitle + entityContainer) and D1's ConnectionFileLocator, then loads
/// the page fresh from disk — so a link to a page in an unloaded collection still opens.
/// Returns nil for a phantom / ambiguous-duplicate / unreadable target (caller no-ops).
enum WikiLinkPageOpener {
    @MainActor
    static func pageSelection(forTitle titleOrID: String, index: PommoraIndex, nexusRootURL: URL) async -> SidebarSelection? {
        let query = IndexQuery(index)
        // Accept either a display title (typed link) or a stored page ID (from
        // .wikiLinkID, set when autocomplete was used to pick the target).
        guard let id = query.resolvePageByIDOrTitle(titleOrID) else { return nil }
        guard
            let container = try? await query.entityContainer(id: id, kind: .page),
            let url = ConnectionFileLocator.locate(id: id, kind: .page, container: container, nexusRoot: nexusRootURL),
            let pf = try? PageFile.loadLenient(from: url, nexusRoot: nexusRootURL)
        else { return nil }
        return .page(PageMeta(id: id, title: pf.title, url: url, frontmatter: pf.frontmatter))
    }
}
