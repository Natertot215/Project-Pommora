import SwiftUI

/// The Homepage detail surface — a per-Nexus dashboard. Its banner is a bounded
/// band (the shared `BannerView`, identical to the content-view banner) with the
/// folder title overlaid bottom-leading (no icon), a divider, then the empty body
/// where the composed-blocks editor lands. Future widgets overlay the band; the
/// body holds block content — neither is scoped yet.
///
/// Distinct from the content-view banner only in that there's no data table
/// beneath, so the band sits in a simple `VStack { band; Divider; body }`. The band
/// persists through `HomepageManager.setBanner`, keyed by the literal `"homepage"`
/// (the singleton has no entity id — its location IS its identity).
struct HomepageDetailView: View {
    @Environment(NexusManager.self) private var nexusManager
    @Environment(HomepageManager.self) private var homepageManager

    /// Asset-folder key for the homepage singleton (`.nexus/assets/homepage/`).
    private static let assetKey = "homepage"

    /// The nexus folder name — the homepage shows the title only, no icon.
    private var title: String {
        nexusManager.currentNexus?.rootURL.lastPathComponent ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRegion
            Divider()
            // Homepage body — the composed-blocks editor lands here; empty for now.
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Banner + title. With a banner set the title overlays the band's
    /// bottom-leading edge (the band is the background; the overlay is the future
    /// widget surface); without one, the band shows its Add-Banner affordance with
    /// the plain title below — identical to the content-view header's two states.
    @ViewBuilder
    private var headerRegion: some View {
        if let nexus = nexusManager.currentNexus {
            if let banner = homepageManager.homepage.banner {
                bannerBand(banner, in: nexus)
                    .backgroundExtensionEffect()
                    .overlay(alignment: .bottomLeading) {
                        titleLabel
                            .padding(.horizontal, PUI.DetailHeader.paddingHorizontal)
                            .padding(.bottom, PUI.DetailHeader.overlayInset)
                    }
            } else {
                bannerBand(nil, in: nexus)
                header
            }
        }
    }

    /// The shared banner mechanism, wired to the homepage's persistence.
    private func bannerBand(_ path: String?, in nexus: Nexus) -> some View {
        BannerView(
            bannerPath: path,
            nexus: nexus,
            assetKey: Self.assetKey,
            setBanner: { try await homepageManager.setBanner($0) },
            reportError: { homepageManager.pendingError = $0 }
        )
    }

    /// Title only, no icon — content-view header font.
    private var titleLabel: some View {
        Text(title)
            .font(PUI.DetailHeader.titleFont)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// No-banner plain chrome — title at top-leading, content-view insets.
    private var header: some View {
        HStack {
            titleLabel
            Spacer()
        }
        .padding(.horizontal, PUI.DetailHeader.paddingHorizontal)
        .padding(.vertical, PUI.DetailHeader.paddingVertical)
    }
}
