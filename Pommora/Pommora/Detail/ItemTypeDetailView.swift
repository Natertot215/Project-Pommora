import SwiftUI

/// Detail-pane stub for an Item Type selection.
///
/// ParadigmV2 (Task 8.4): The real Items-table surface (parallel to
/// `PageTypeDetailView`) ships in a follow-up plan. This stub keeps
/// sidebar selection routing build-clean — clicks land somewhere, the
/// destination is just a placeholder.
///
/// Does NOT read SettingsManager labels — title comes directly from
/// `type.title` per spec. Does NOT inject any managers.
struct ItemTypeDetailView: View {
    let type: ItemType

    var body: some View {
        ContentUnavailableView(
            type.title,
            systemImage: "tray",
            description: Text("Items table ships in a follow-up plan. The Item Type exists on disk and via the data manager; UI lands later.")
        )
    }
}
