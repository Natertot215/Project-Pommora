import SwiftUI

/// Root menu rendered inside the View Settings popover for the storage
/// scopes (PageCollection / PageCollection).
///
/// Mirrors Notion's view-settings dropdown shape — header (icon + title,
/// both inline-editable for both storage scopes) + a stack of pane
/// rows. Active rows: Edit Properties + Layout + Group + Filter + Sort; the
/// Templates row renders muted, pointing at a later patch.
///
/// Header inline edits (both storage scopes — Types and Collections
/// alike; Collections carry their own icon since #45 and rename via the
/// atomic folder-move rename methods):
///   - Click icon → SymbolPicker popover → commits via updatePageCollectionIcon /
///     updatePageCollectionIcon
///   - Click title → inline TextField → commits via renamePageCollection /
///     renamePageCollection on submit
///
/// Push behavior lives at the popover level — this view appends routes to
/// the `path` binding passed from the popover.
struct StorageMenuRoot: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageCollectionManager.self) private var collectionManager
    @Environment(PageSetManager.self) private var pageSetManager

    @State private var iconPickerOpen: Bool = false
    @State private var isRenaming: Bool = false
    @State private var renameDraft: String = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        ViewSettingsPane {
            // Pinned header: editable icon + title, then the divider.
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, PUI.Pane.Header.paddingHorizontal)
                    .padding(.top, PUI.Pane.Header.paddingTop)
                    .padding(.bottom, PUI.Pane.Header.paddingBottom)
                PaneDivider()
            }
        } content: {
            VStack(spacing: 0) {
                activeRow(
                    icon: "list.bullet.rectangle",
                    title: "Edit Properties",
                    route: .editProperties
                )
                activeRow(
                    icon: "rectangle.3.group",
                    title: "Layout",
                    route: .layout
                )
                mutedRow(icon: "doc.on.doc", title: "Templates")
                activeRow(
                    icon: "square.stack.3d.down.right",
                    title: "Group",
                    route: .group
                )
                activeRow(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "Filter",
                    route: .filter
                )
                activeRow(
                    icon: "arrow.up.arrow.down",
                    title: "Sort",
                    route: .sort
                )
            }
            .padding(.vertical, PUI.Spacing.xs)
        } footer: {
            openInFooter
        }
    }

    /// Pinned open-in footer (vault-scoped, decision #2): an `Open Pages In`
    /// selector below a trailing divider, rendered as the shared
    /// `LabeledMenuSelector` (label left, value-dropdown right) so it reads
    /// identically to the Edit-Property "Display As" picker. Writes
    /// `PageCollection.open_in` via `setOpenIn`. Labels are structural — NOT
    /// user-renameable. (The "Layout" name now belongs to the Layout pane row.)
    @ViewBuilder
    private var openInFooter: some View {
        if case .pageCollection(let livePageCollection) = liveScope {
            Divider()
            LabeledMenuSelector(
                title: "Open Pages In",
                value: (livePageCollection.openIn ?? .window).displayLabel
            ) {
                Picker(
                    "Open Pages In",
                    selection: Binding(
                        get: { livePageCollection.openIn ?? .window },
                        set: { mode in
                            Task { try? await collectionManager.setOpenIn(mode, forPageCollection: livePageCollection.id) }
                        }
                    )
                ) {
                    ForEach(OpenInMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: PUI.Pane.Header.interSpacing) {
            iconAffordance
            titleAffordance
        }
    }

    /// Tappable icon for every storage scope — opens the SymbolPicker
    /// popover. The faint rounded-rectangle background matches the
    /// OptionEditPopover title-pill emphasis (per Nathan's 2026-05-26
    /// direction).
    @ViewBuilder
    private var iconAffordance: some View {
        Button {
            iconPickerOpen = true
        } label: {
            Image(systemName: headerIcon)
                .font(PUI.Icon.header)
                .foregroundStyle(.primary)
                .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
                .fieldBackground()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit Icon")
        // Pommora-native IconPicker (compact single-glass popover) — replaces
        // the third-party SymbolPicker, which hardcoded a 540-wide macOS frame.
        .iconPickerPopover(isPresented: $iconPickerOpen, symbol: iconBinding)
    }

    /// Tappable title for every storage scope — click to reveal an inline
    /// rename TextField (commits on submit/blur). Shares the faint pill
    /// background with OptionEditPopover title emphasis (per Nathan's
    /// 2026-05-26 direction).
    @ViewBuilder
    private var titleAffordance: some View {
        if isRenaming {
            TextField("Title", text: $renameDraft)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, PUI.Spacing.lg)
                .padding(.vertical, PUI.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldBackground()
                .focused($renameFocused)
                .onAppear {
                    renameDraft = headerTitle
                    renameFocused = true
                }
                .onSubmit { Task { await commitRename() } }
                .onChange(of: renameFocused) { wasFocused, isFocused in
                    // Commit on click-out (blur), not just Enter.
                    if wasFocused && !isFocused { Task { await commitRename() } }
                }
        } else {
            Button {
                renameDraft = headerTitle
                isRenaming = true
            } label: {
                Text(headerTitle)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, PUI.Spacing.lg)
                    .padding(.vertical, PUI.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldBackground()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Title")
        }
    }

    private var headerTitle: String {
        switch liveScope {
        case .pageCollection(let t): return t.title
        case .pageSet(let c): return c.title
        default: return "View Settings"
        }
    }

    private var headerIcon: String {
        switch liveScope {
        case .pageCollection(let t): return t.icon ?? "folder"
        case .pageSet(let c): return c.icon ?? "folder"
        default: return "slider.horizontal.3"
        }
    }

    /// `scope` re-resolved against the live `@Observable` managers so the header
    /// icon + title update the instant an edit commits. The captured `scope` is a
    /// value snapshot — reading it never re-renders on a manager change; reading
    /// the managers here registers the observation dependency (mirrors the detail
    /// views' `livePageCollection` / `liveCollection`). Falls back to the snapshot when
    /// the entity isn't resolvable (e.g. mid-delete).
    private var liveScope: ViewSettingsScope {
        switch scope {
        case .pageCollection(let t):
            return .pageCollection(collectionManager.types.first(where: { $0.id == t.id }) ?? t)
        case .pageSet(let c):
            return .pageSet(
                collectionManager.pageCollectionsByType[c.parentID]?.first(where: { $0.id == c.id }) ?? c)
        default:
            return scope
        }
    }

    // MARK: - Inline-edit commits

    /// Two-way binding for the SymbolPicker — get returns the current
    /// icon, set fires the right `updateXxxIcon` manager method.
    private var iconBinding: Binding<String?> {
        Binding(
            get: { headerIcon },
            set: { newIcon in
                Task { await commitIcon(newIcon) }
            }
        )
    }

    private func commitIcon(_ newIcon: String?) async {
        switch liveScope {
        case .pageCollection(let t):
            try? await collectionManager.updatePageCollectionIcon(t, to: newIcon)
        case .pageSet(let s):
            try? await pageSetManager.updatePageSetIcon(s, to: newIcon)
        default:
            break
        }
    }

    private func commitRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        defer { isRenaming = false }
        guard !trimmed.isEmpty, trimmed != headerTitle else { return }
        switch liveScope {
        case .pageCollection(let t):
            try? await collectionManager.renamePageCollection(t, to: trimmed)
        case .pageSet(let s):
            try? await pageSetManager.renamePageSet(s, to: trimmed)
        default:
            break
        }
    }

    @ViewBuilder
    private func activeRow(icon: String, title: String, route: ViewSettingsRoute) -> some View {
        Button {
            path.append(route)
        } label: {
            HStack(spacing: PUI.Row.interSpacing) {
                Image(systemName: icon)
                    .font(PUI.Icon.leading)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.leadingFrame)
                Text(title)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(PUI.Icon.chevron)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, PUI.Row.paddingHorizontal)
            .padding(.vertical, PUI.Row.paddingVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Muted placeholder row — no chevron, no destination, no right-side
    /// version annotation (per Nathan's "DO NOT say 'coming v0.X.X' just keep
    /// it muted" directive). The row renders at the same dimensions as an
    /// activeRow so the muted/active distinction is purely tonal.
    @ViewBuilder
    private func mutedRow(icon: String, title: String) -> some View {
        HStack(spacing: PUI.Row.interSpacing) {
            Image(systemName: icon)
                .font(PUI.Icon.leading)
                .foregroundStyle(.tertiary)
                .frame(width: PUI.Icon.leadingFrame)
            Text(title)
                .font(PUI.Typography.row)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, PUI.Row.paddingVertical)
    }
}

#if DEBUG
#Preview("Storage menu — PageCollection") {
    StorageMenuRoot(
        scope: .pageCollection(
            PageCollection(
                id: "01HPT", title: "Notes", icon: "note.text",
                properties: [], views: [], modifiedAt: Date()
            )
        ),
        path: .constant([])
    )
}
#endif
