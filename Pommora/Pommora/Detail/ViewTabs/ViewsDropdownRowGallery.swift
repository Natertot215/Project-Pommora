import SwiftUI

/// Component Library staging for the Views dropdown row (`ViewsPanelRow`) — the
/// design source per the HARD RULE. Renders the row variants on the shared
/// `.chipDropdownPanel()` surface at the production 280pt width so the dropdown
/// can be tuned here before pulling into the live toolbar popover.
struct ViewsDropdownRowGallery: View {
    private let tableView = SavedView(
        id: "view_sample_table", name: "All Pages", icon: "tablecells", type: .table)
    private let gallerySmall = SavedView(
        id: "view_sample_gallery_s", name: "Covers", icon: "square.grid.3x3",
        type: .gallery, cardSize: .small)
    private let galleryLarge = SavedView(
        id: "view_sample_gallery_l", name: "Showcase", icon: "photo",
        type: .gallery, cardSize: .large)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Views Dropdown Rows")
                .font(.headline)

            VStack(spacing: 0) {
                stagedRow(tableView, isActive: true)
                stagedRow(gallerySmall, isActive: false)
                stagedRow(galleryLarge, isActive: false)
            }
            .padding(.vertical, 6)
            .frame(width: 280)
            .chipDropdownPanel()
        }
    }

    private func stagedRow(_ view: SavedView, isActive: Bool) -> some View {
        ViewsPanelRow(
            view: view,
            isActive: isActive,
            isTypeExpanded: false,
            onSelect: {},
            onToggleType: {},
            onPickIcon: {},
            onRename: { _ in },
            onDuplicate: {},
            onDelete: {},
            canDelete: true
        )
    }
}
