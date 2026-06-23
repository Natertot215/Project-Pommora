import Nuke
import NukeUI
import SwiftUI
import UniformTypeIdentifiers

/// Top-of-sidebar identity banner — the per-Nexus profile image, the nexus title
/// (its folder name), and a subtitle (custom text, or today's date by default).
/// Replaces the former "Homepage" saved-leaf and is the FIRST row of the sidebar
/// List (its own Section) so it scrolls with everything else; selection +
/// highlight ride the native List mechanism (`.tag` + `.listRowBackground` at the
/// SidebarView call site, quirk #6/#7), not an in-content `.background`.
///
/// Editing is right-click-driven and SCOPED to each element: right-click the
/// avatar → picture actions, the title → Rename (renames the nexus folder), the
/// subtitle → Edit Subtitle. Inline edits mirror `RenameableRow`'s commit/cancel.
struct NexusHeaderBanner: View {
    @Environment(NexusManager.self) private var nexusManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var isImportingImage = false

    // Inline title rename (renames the nexus root folder via NexusManager).
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isCommittingTitle = false
    @FocusState private var titleFocused: Bool

    // Inline subtitle edit.
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

    var body: some View {
        // spacing 8 matches the native row icon→label gap (SelectableRow /
        // TierDisclosureRow both use HStack(spacing: 8)).
        HStack(spacing: PUI.Spacing.md) {
            avatar
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .contextMenu { avatarMenu }
            // Natural height + HStack centering sits the text block on the
            // avatar's mid-line.
            VStack(alignment: .leading, spacing: PUI.Spacing.xxs) {
                titleSlot
                subtitleSlot
            }
        }
        .padding(.vertical, PUI.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let source = urls.first else { return }
            importImage(from: source)
        }
        .fileDialogMessage("Choose a profile picture for this nexus")
    }

    // MARK: - Title / Subtitle slots (shared inline-edit primitive)

    private var titleSlot: some View {
        InlineEditField(
            value: title,
            placeholder: "Name",
            font: PUI.Typography.paneTitle,
            foreground: .primary,
            menuLabel: "Rename",
            isEditing: $isEditingTitle,
            draft: $titleDraft,
            focused: $titleFocused,
            begin: beginTitleEdit,
            commit: commitTitle,
            cancel: cancelTitleEdit
        )
    }

    private var subtitleSlot: some View {
        InlineEditField(
            value: displaySubtitle,
            placeholder: "Subtitle",
            font: .subheadline,
            foreground: .secondary,
            menuLabel: "Edit Subtitle",
            isEditing: $isEditingSubtitle,
            draft: $subtitleDraft,
            focused: $subtitleFocused,
            begin: beginSubtitleEdit,
            commit: commitSubtitle,
            cancel: cancelSubtitleEdit
        )
    }

    // MARK: - Avatar (scoped menu)

    @ViewBuilder
    private var avatarMenu: some View {
        Button(hasImage ? "Change Picture" : "Add Picture") { isImportingImage = true }
        if hasImage {
            Button("Remove Picture", role: .destructive) { removeImage() }
        }
    }

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

    // MARK: - Title rename (mirrors RenameableRow commit / cancel)

    private func beginTitleEdit() {
        titleDraft = title
        isEditingTitle = true
    }

    private func commitTitle() {
        guard isEditingTitle, !isCommittingTitle else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != title else {
            isEditingTitle = false
            return
        }
        isCommittingTitle = true
        Task {
            // Renames the nexus root folder (prompts for parent access if needed).
            // A successful rename republishes currentNexus, which rebuilds this
            // view — so resetting the flags below is best-effort.
            await nexusManager.renameRoot(to: trimmed)
            isEditingTitle = false
            isCommittingTitle = false
        }
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        isCommittingTitle = false
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

// MARK: - Inline-edit primitive

/// A right-click-to-edit text line: a `Text` with a scoped context menu when
/// idle, an in-place `TextField` (auto-focused, submit/escape/blur-aware) when
/// editing. Each instance keeps its own `@FocusState` upstream and hands its
/// binding down, since `@FocusState` wrappers can't be shared across views.
/// Commit/cancel/begin are caller-owned closures, so each field keeps its own
/// exact commit semantics (trim-and-guard vs. defer-to-manager).
private struct InlineEditField: View {
    let value: String
    let placeholder: String
    let font: Font
    let foreground: HierarchicalShapeStyle
    let menuLabel: String

    @Binding var isEditing: Bool
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding

    let begin: () -> Void
    let commit: () -> Void
    let cancel: () -> Void

    var body: some View {
        if isEditing {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(foreground)
                .focused(focused)
                .onSubmit { commit() }
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
                .onChange(of: focused.wrappedValue) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onAppear { focused.wrappedValue = true }
        } else {
            Text(value)
                .font(font)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .contextMenu { Button(menuLabel) { begin() } }
        }
    }
}
