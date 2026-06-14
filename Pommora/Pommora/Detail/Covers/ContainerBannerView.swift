import Nuke
import NukeUI
import SwiftUI
import UniformTypeIdentifiers

/// Full-width banner area shown above a container's (PageType / PageCollection)
/// title. ABSENT entirely when `bannerPath == nil` — except for a floating
/// **Add Banner** button (the page add-icon hover pattern) that appears only in
/// the no-banner state. When set, renders the image via NukeUI from the
/// nexus-relative banner path; the set state carries a Change / Remove context
/// menu (mirrors the cover menu's Set / Change / Remove). Renders nothing when
/// `isVisible` is false (the active view's Display Banner toggle is off).
///
/// Banner persistence runs through `PageTypeManager.setBanner` (Task-3 disk
/// pattern); the file is copied via `CoverAssetStore` first (same security-scope
/// sequence as the cover importer). This view owns the importer and hands the
/// resulting nexus-relative path to `setBanner` via the manager.
struct ContainerBannerView: View {
    let containerID: String
    let bannerPath: String?
    /// Whether the active view shows this container's banner (the Layout pane's
    /// Display Banner toggle). When false the area renders nothing — not even the
    /// Add Banner affordance — so the toggle actually gates visibility.
    var isVisible: Bool = true
    let nexus: Nexus

    @Environment(PageTypeManager.self) private var pageTypeManager
    @State private var isImporting: Bool = false
    @State private var isHovering: Bool = false

    private static let bannerHeight: CGFloat = 180

    var body: some View {
        Group {
            if !isVisible {
                EmptyView()
            } else if let bannerPath {
                LazyImage(request: bannerRequest(bannerPath)) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color(.quaternarySystemFill)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.bannerHeight)
                .clipped()
                .contextMenu { bannerMenu(current: bannerPath) }
            } else {
                addBannerAffordance
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let source = urls.first else { return }
            importBanner(from: source)
        }
    }

    /// Set-state context menu — Change re-fires the importer; Remove clears the
    /// banner then deletes its asset file (delete-after-write, mirroring the
    /// cover menu's Set / Change / Remove pattern).
    @ViewBuilder
    private func bannerMenu(current: String) -> some View {
        Button("Change Banner") { isImporting = true }
        Button("Remove Banner", role: .destructive) { removeBanner(current) }
    }

    /// The no-banner state: a slim floating "Add Banner" button revealed on
    /// hover (mirrors the page add-icon hover pattern).
    private var addBannerAffordance: some View {
        HStack {
            Button {
                isImporting = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.app")
                        .font(.system(size: 14))
                    Text("Add Banner")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a banner")
            .accessibilityLabel("Add banner")
            .opacity(isHovering ? 1 : 0)
            Spacer()
        }
        .padding(.horizontal, PUI.Spacing.xl)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private func bannerRequest(_ path: String) -> ImageRequest {
        let url = AssetURLResolver.fileURL(forRelativePath: path, in: nexus)
        return ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(width: 1200)]
        )
    }

    /// Copy the source inside the scoped window, then persist via setBanner. A
    /// container's banner asset folder is keyed by the container's own id, so the
    /// store and the `setBanner` routing share `containerID`.
    private func importBanner(from source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let store = CoverAssetStore()
        let previousBanner = bannerPath
        let relativePath: String
        do {
            relativePath = try store.storeSync(image: source, for: containerID, in: nexus)
        } catch {
            // Copy failed inside the scoped window; surface via the manager's
            // pendingError so SidebarToast shows it (same toast path as setBanner).
            pageTypeManager.pendingError = error
            return
        }
        let containerID = containerID
        Task {
            do {
                try await pageTypeManager.setBanner(relativePath, forContainer: containerID)
                // Delete the replaced banner file ONLY AFTER the write succeeds,
                // so a failed write never leaves `banner` pointing at a deleted file.
                store.delete(relativePath: previousBanner, for: containerID, in: nexus)
            } catch {}
        }
    }

    /// Clears the container's banner, then deletes the now-orphaned asset file —
    /// only AFTER the `setBanner(nil)` write succeeds, so a failed write never
    /// leaves `banner` pointing at a deleted file (mirrors `removeCover`).
    private func removeBanner(_ current: String) {
        let store = CoverAssetStore()
        let containerID = containerID
        Task {
            do {
                try await pageTypeManager.setBanner(nil, forContainer: containerID)
                store.delete(relativePath: current, for: containerID, in: nexus)
            } catch {}
        }
    }
}
