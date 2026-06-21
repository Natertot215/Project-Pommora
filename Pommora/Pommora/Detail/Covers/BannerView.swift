import Nuke
import NukeUI
import SwiftUI
import UniformTypeIdentifiers

/// The shared banner mechanism behind both the content-view container banner
/// (`ContainerBannerView`) and the homepage banner (`HomepageDetailView`): a
/// full-width bounded image band (`PUI.DetailHeader.bannerHeight`) when a banner
/// is set, a hover-revealed "Add Banner" affordance when not, the Change / Remove
/// context menu, and the `CoverAssetStore` import / remove (delete-after-write).
///
/// The two owners differ only in WHERE the banner persists and under WHICH asset
/// key, so those are injected: `assetKey` for `CoverAssetStore`, a `setBanner`
/// closure for the owning manager, and a `reportError` sink for that manager's
/// `pendingError`. Callers own the title chrome — `ViewSurface` overlays the
/// container title, `HomepageDetailView` the folder title — so this view renders
/// the band / affordance only, never a title.
struct BannerView: View {
    let bannerPath: String?
    /// Whether the owning view shows the banner (the container's Display Banner
    /// toggle). When false the band renders nothing — not even the affordance.
    var isVisible: Bool = true
    let nexus: Nexus
    /// `CoverAssetStore` entity key — a container ULID, or the literal "homepage".
    let assetKey: String
    /// Persists the new banner path (or nil to clear) on the owning manager.
    let setBanner: @MainActor (String?) async throws -> Void
    /// Routes an import failure to the owning manager's `pendingError` (toast).
    let reportError: @MainActor (any Error) -> Void

    @State private var isImporting = false
    @State private var isHovering = false

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
                .frame(height: PUI.DetailHeader.bannerHeight)
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

    /// Set-state context menu — Change re-fires the importer; Remove clears + deletes.
    @ViewBuilder
    private func bannerMenu(current: String) -> some View {
        Button("Change Banner") { isImporting = true }
        Button("Remove Banner", role: .destructive) { removeBanner(current) }
    }

    /// No-banner state — a slim "Add Banner" button revealed on hover.
    private var addBannerAffordance: some View {
        HStack {
            Button {
                isImporting = true
            } label: {
                HStack(spacing: PUI.Spacing.xs) {
                    Image(systemName: "plus.app").font(.system(size: 14))
                    Text("Add Banner").font(.caption)
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
        return ImageRequest(url: url, processors: [ImageProcessors.Resize(width: 1200)])
    }

    /// Copy the source inside the scoped window, then persist via `setBanner`,
    /// deleting the replaced asset only AFTER the write succeeds — so a failed
    /// write never leaves the banner pointing at a deleted file.
    private func importBanner(from source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let store = CoverAssetStore()
        let previous = bannerPath
        let assetKey = assetKey
        let nexus = nexus
        let setBanner = setBanner
        let relativePath: String
        do {
            relativePath = try store.storeSync(image: source, for: assetKey, in: nexus)
        } catch {
            reportError(error)
            return
        }
        Task {
            do {
                try await setBanner(relativePath)
                store.delete(relativePath: previous, for: assetKey, in: nexus)
            } catch {}
        }
    }

    /// Clears the banner, then deletes the orphaned asset — only AFTER the write
    /// succeeds (mirrors `importBanner`'s delete-after-write).
    private func removeBanner(_ current: String) {
        let store = CoverAssetStore()
        let assetKey = assetKey
        let nexus = nexus
        let setBanner = setBanner
        Task {
            do {
                try await setBanner(nil)
                store.delete(relativePath: current, for: assetKey, in: nexus)
            } catch {}
        }
    }
}
