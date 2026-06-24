import SwiftUI

/// Content-view banner — the per-container banner above a PageCollection / PageCollection
/// title. A thin wrapper over the shared `BannerView`, wiring it to the container's
/// persistence (`PageCollectionManager.setBanner(forContainer:)`) and asset key (the
/// container id). Display, import/remove, and the Add / Change / Remove affordances
/// all live in `BannerView`; `ViewSurface` overlays the title.
struct ContainerBannerView: View {
    let containerID: String
    let bannerPath: String?
    /// Whether the active view shows this container's banner (the Layout pane's
    /// Display Banner toggle). When false the area renders nothing.
    var isVisible: Bool = true
    let nexus: Nexus

    @Environment(PageCollectionManager.self) private var collectionManager

    var body: some View {
        BannerView(
            bannerPath: bannerPath,
            isVisible: isVisible,
            nexus: nexus,
            assetKey: containerID,
            setBanner: { try await collectionManager.setBanner($0, forContainer: containerID) },
            reportError: { collectionManager.pendingError = $0 }
        )
    }
}
