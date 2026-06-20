import Nuke
import NukeUI
import SwiftUI
import UniformTypeIdentifiers

/// Top-of-sidebar identity banner — the per-Nexus profile image, the nexus title
/// (its folder name), and a subtitle (custom text, or today's date by default).
/// Replaces the former "Homepage" saved-leaf: tapping selects the Homepage
/// surface; the selection fill hugs the content (gaps live outside it) and is
/// inset on the right to clear the NavigationSplitView splitter.
///
/// Editing is right-click-driven: the context menu changes / removes the picture
/// and begins inline subtitle editing (mirrors `RenameableRow`'s commit/cancel).
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

    /// Avatar diameter; the initial glyph scales off it (single source of truth).
    private let avatarSize: CGFloat = 38

    /// The nexus title IS its folder name (filename = title; no display-name field).
    private var title: String {
        nexusManager.currentNexus?.rootURL.lastPathComponent ?? ""
    }

    /// Custom subtitle when set; otherwise today's date as the default line.
    private var displaySubtitle: String {
        let custom = settingsManager.settings.profileSubtitle
        return custom.isEmpty ? Self.formattedToday() : custom
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
        // spacing 8 matches the native row icon→label gap (SelectableRow /
        // TierDisclosureRow both use HStack(spacing: 8)).
        HStack(spacing: 8) {
            avatar
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
            // Natural height + HStack centering sits the text block on the
            // avatar's mid-line.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PUI.Typography.paneTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitleSlot
            }
        }
        // Leading tuned so the avatar's center aligns with the disclosure-row
        // icons (Areas / Vaults), which sit indented behind their chevron.
        .padding(.leading, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Fill hugs the content. Right inset (16) > left (11) so the rounded
            // corner clears the splitter; left matches the row SelectionChrome.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlight)
                .padding(EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 16))
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
        .fileDialogMessage("Choose a profile picture for this nexus")
        // Outer gaps — above to the toolbar (minimal; the bulk of that space is
        // macOS's own toolbar inset, which the header sits below), below to
        // "Contexts" (roomier so the header isn't squished against it).
        .padding(.top, 2)
        .padding(.bottom, 13)
    }

    @ViewBuilder
    private var subtitleSlot: some View {
        if isEditingSubtitle {
            TextField("Subtitle", text: $subtitleDraft)
                .textFieldStyle(.plain)
                .font(.subheadline)
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
        } else {
            Text(displaySubtitle)
                .font(.subheadline)
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
                // Scales with the one avatarSize source rather than a 2nd constant.
                .font(.system(size: avatarSize * 0.45, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var initial: String {
        title.first.map { String($0).uppercased() } ?? "•"
    }

    private func avatarRequest(_ path: String, in nexus: Nexus) -> ImageRequest {
        let url = AssetURLResolver.fileURL(forRelativePath: path, in: nexus)
        return ImageRequest(url: url, processors: [ImageProcessors.Resize(width: 128)])
    }

    // MARK: - Today's date (default subtitle)

    /// "June 19th 2026" — full month, ordinal day, year.
    private static func formattedToday() -> String {
        let now = Date()
        let cal = Calendar.current
        let day = cal.component(.day, from: now)
        let year = cal.component(.year, from: now)
        let month = now.formatted(.dateTime.month(.wide))
        return "\(month) \(day)\(ordinalSuffix(day)) \(year)"
    }

    private static func ordinalSuffix(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // MARK: - Image edit (mirrors ContainerBannerView's scoped import)

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
