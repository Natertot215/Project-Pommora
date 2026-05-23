import SwiftUI

/// Detail-pane stub for an Item Collection selection.
///
/// ParadigmV2 (Task 8.4): The real Items-table surface (parallel to
/// `PageCollectionDetailView`) ships in a follow-up plan. This stub keeps
/// sidebar selection routing build-clean — clicks land somewhere, the
/// destination is just a placeholder.
///
/// Does NOT read SettingsManager labels — title comes directly from
/// `collection.title` per spec. Does NOT inject any managers.
struct ItemCollectionDetailView: View {
    let collection: ItemCollection

    var body: some View {
        ContentUnavailableView(
            collection.title,
            systemImage: "tray.fill",
            description: Text(
                "Items table ships in a follow-up plan. The Item Collection exists on disk and via the data manager; UI lands later."
            )
        )
    }
}
