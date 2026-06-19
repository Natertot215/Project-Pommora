import Nuke
import NukeUI
import SwiftUI
import UniformTypeIdentifiers

/// Top-of-sidebar identity banner — the per-Nexus profile image, the nexus
/// title (its folder name), and a custom subtitle. Replaces the former
/// "Homepage" saved-leaf: tapping the banner selects the Homepage surface.
///
/// Editing is right-click-driven (matching every other sidebar entity): the
/// context menu changes / removes the picture and begins inline subtitle edit;
/// the inline subtitle field mirrors `RenameableRow`'s commit / cancel contract.
/// Lives in the sidebar VStack ABOVE the List (outside Section layout) so its
/// distinct shape never reaches `OutlineListCoordinator`'s row diff (quirk #8/#9).
struct NexusHeaderBanner: View {
    @Binding var selection: SidebarSelection

    @Environment(NexusManager.self) private var nexusManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var hovering = false
    @State private var isImportingImage = false

    // Inline subtitle edit (mirrors RenameableRow's draft / commit / cancel).
    @State private var isEditingSubtitle = false
    @State private var subtitleDraft = ""
    @State private var isCommittingSubtitle = false
    @FocusState private var subtitleFocused: Bool

    /// The nexus title IS its folder name (filename = title; no display-name field).
    private var title: String {
        nexusManager.currentNexus?.rootURL.lastPathComponent ?? ""
    }

    private var subtitle: String {
        settingsManager.settings.profileSubtitle
    }

    private var hasImage: Bool {
        !(settingsManager.settings.profileImage ?? "").isEmpty
    }

    /// Homepage is the banner's destination — highlight it while selected.
    private var isHomepageSelected: Bool {
        if case .savedKey(let key) = selection { return key == "homepage" }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 38, height: 38)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitleSlot
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlight)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isEditingSubtitle { selection = .savedKey("homepage") } }
        .onHover { hovering = $0 }
        .contextMenu { bannerMenu }
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let source = urls.first else { return }
            importImage(from: source)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var subtitleSlot: some View {
        if isEditingSubtitle {
            TextField("Subtitle", text: $subtitleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .focused($subtitleFocused)
                .onSubmit { commitSubtitle() }
                .onKeyPress(.escape) {
                    cancelSubtitleEdit()
                    return .handled
                }
                .onChange(of: subtitleFocused) { _, focused in
                    if !focused { commitSubtitle() }
                }
                .onAppear { subtitleFocused = true }
        } else if !subtitle.isEmpty {
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var bannerMenu: some View {
        Button(hasImage ? "Change Picture" : "Add Picture") { isImportingImage = true }
        if hasImage {
            Button("Remove Picture", role: .destructive) { removeImage() }
        }
        Button("Edit Subtitle") { beginSubtitleEdit() }
    }

    private var highlight: Color {
        if isHomepageSelected { return Color(nsColor: .quaternarySystemFill) }
        if hovering { return Color(nsColor: .quaternarySystemFill).opacity(0.5) }
        return .clear
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        if let path = settingsManager.settings.profileImage, !path.isEmpty,
            let nexus = nexusManager.currentNexus {
            LazyImage(request: avatarRequest(path, in: nexus)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    defaultAvatar
                }
            }
        } else {
            defaultAvatar
        }
    }

    /// Initial-on-tinted-circle — the Apple-idiomatic photo fallback (Contacts /
    /// Mail) when no profile image is set.
    private var defaultAvatar: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.18))
            Text(initial)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var initial: String {
        title.first.map { String($0).uppercased() } ?? "•"
    }

    private func avatarRequest(_ path: String, in nexus: Nexus) -> ImageRequest {
        let url = AssetURLResolver.fileURL(forRelativePath: path, in: nexus)
        return ImageRequest(url: url, processors: [ImageProcessors.Resize(width: 96)])
    }

    // MARK: - Image edit (mirrors ContainerBannerView's scoped import)

    /// Copies the chosen image into the nexus's own assets folder (entity = the
    /// nexus ULID) inside the security-scoped window, then persists the relative
    /// path; the replaced asset is deleted only after the new path lands.
    private func importImage(from source: URL) {
        guard let nexus = nexusManager.currentNexus else { return }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let store = CoverAssetStore()
        let previous = settingsManager.settings.profileImage
        let relativePath: String
        do {
            relativePath = try store.storeSync(image: source, for: nexus.id, in: nexus)
        } catch {
            settingsManager.pendingError = error
            return
        }
        Task {
            await settingsManager.updateProfileImage(relativePath)
            if settingsManager.settings.profileImage == relativePath {
                store.delete(relativePath: previous, for: nexus.id, in: nexus)
            }
        }
    }

    private func removeImage() {
        guard let nexus = nexusManager.currentNexus else { return }
        let previous = settingsManager.settings.profileImage
        let store = CoverAssetStore()
        Task {
            await settingsManager.updateProfileImage(nil)
            if settingsManager.settings.profileImage == nil {
                store.delete(relativePath: previous, for: nexus.id, in: nexus)
            }
        }
    }

    // MARK: - Subtitle edit (mirrors RenameableRow commit / cancel)

    private func beginSubtitleEdit() {
        subtitleDraft = settingsManager.settings.profileSubtitle
        isEditingSubtitle = true
    }

    private func commitSubtitle() {
        guard isEditingSubtitle, !isCommittingSubtitle else { return }
        isCommittingSubtitle = true
        let text = subtitleDraft
        Task {
            await settingsManager.updateProfileSubtitle(text)
            isEditingSubtitle = false
            isCommittingSubtitle = false
        }
    }

    private func cancelSubtitleEdit() {
        isEditingSubtitle = false
        isCommittingSubtitle = false
    }
}
