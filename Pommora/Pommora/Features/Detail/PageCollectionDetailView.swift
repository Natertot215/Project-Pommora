import SwiftUI

/// Collection detail pane — a thin shell over `ViewSurface` in collection scope. Holds no
/// state and no environment of its own (everything lives in `ViewSurface`); its
/// only job is to keep the public init `SidebarDetailView` calls byte-identical
/// while delegating the whole render to the shared surface.
struct PageCollectionDetailView: View {
    let pageCollection: PageCollection
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page visited before navigating back to this collection; shown as a
    /// ghost trail crumb if the page lives at this collection's root.
    var trailPage: PageMeta? = nil

    var body: some View {
        ViewSurface(
            scope: PageCollectionScope(pageCollection: pageCollection),
            selection: $selection,
            presentedSheet: $presentedSheet,
            editingID: $editingID,
            justCreatedID: $justCreatedID,
            trailPage: trailPage
        )
    }
}
