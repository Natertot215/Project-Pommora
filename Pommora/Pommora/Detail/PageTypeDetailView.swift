import SwiftUI

/// Vault detail pane — a thin shell over `ViewSurface` in vault scope. Holds no
/// state and no environment of its own (everything lives in `ViewSurface`); its
/// only job is to keep the public init `SidebarDetailView` calls byte-identical
/// while delegating the whole render to the shared surface.
struct PageTypeDetailView: View {
    let pageType: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page visited before navigating back to this vault; shown as a
    /// ghost trail crumb if the page lives at this vault's root.
    var trailPage: PageMeta? = nil

    var body: some View {
        ViewSurface(
            scope: VaultScope(pageType: pageType),
            selection: $selection,
            presentedSheet: $presentedSheet,
            editingID: $editingID,
            justCreatedID: $justCreatedID,
            trailPage: trailPage
        )
    }
}
