import Foundation

/// Resolves a clicked `{{Title}}` to its `Item`, loaded fresh from disk so an item
/// in an unloaded set still opens. nil for phantom / ambiguous-duplicate / unreadable.
enum ItemLinkOpener {
    @MainActor
    static func loadItem(forTitle title: String, index: PommoraIndex, nexusRootURL: URL) async -> Item? {
        let query = IndexQuery(index)
        guard let id = query.resolveUniqueTitle(title, kind: .item) else { return nil }
        guard
            let container = try? await query.entityContainer(id: id, kind: .item),
            let url = ConnectionFileLocator.locate(id: id, kind: .item, container: container, nexusRoot: nexusRootURL),
            let item = try? Item.load(from: url)
        else { return nil }
        return item
    }
}
