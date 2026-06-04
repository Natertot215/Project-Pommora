import SwiftUI

/// Root menu rendered inside the View Settings popover for the four storage
/// scopes (PageType / PageCollection / ItemType / ItemCollection).
///
/// Mirrors Notion's view-settings dropdown shape — header (icon + title,
/// both inline-editable for all four storage scopes) + a stack of pane
/// rows. Two rows are ACTIVE at v0.3.1 (Edit Properties + Property
/// Visibility); the remaining four (Layout / Filter / Sort / Group) render
/// muted as placeholder rows pointing at later v0.3.1.x patches.
///
/// Header inline edits (all four storage scopes — Types and Collections
/// alike; Collections carry their own icon since #45 and rename via the
/// atomic folder-move rename methods):
///   - Click icon → SymbolPicker popover → commits via updatePageTypeIcon /
///     updateItemTypeIcon / updatePageCollectionIcon / updateItemCollectionIcon
///   - Click title → inline TextField → commits via renamePageType /
///     renameItemType / renamePageCollection / renameItemCollection on submit
///
/// Push behavior lives at the popover level — this view appends routes to
/// the `path` binding passed from the popover.
struct StorageMenuRoot: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ItemTypeManager.self) private var itemTypeManager

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
                    icon: "eye",
                    title: "Property Visibility",
                    route: .propertyVisibility
                )
                // ITEM scopes get the live Templates pane (T5.x); PAGE scopes
                // keep the muted placeholder. Branch on the scope-derived side
                // (mirrors PropertyVisibilityPane's `side`) so unmuting an
                // Item Type/Set doesn't also unmute Pages.
                switch side {
                case .items:
                    activeRow(icon: "doc.on.doc", title: "Templates", route: .itemTemplate)
                case .pages, .none:
                    mutedRow(icon: "doc.on.doc", title: "Templates")
                }
                mutedRow(icon: "line.3.horizontal.decrease.circle", title: "Filter")
                mutedRow(icon: "square.stack.3d.down.right", title: "Group")
                mutedRow(icon: "arrow.up.arrow.down", title: "Sort")
            }
            .padding(.vertical, PUI.Spacing.xs)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
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
        case .pageType(let t): return t.title
        case .pageCollection(let c): return c.title
        case .itemType(let t): return t.title
        case .itemCollection(let c): return c.title
        default: return "View Settings"
        }
    }

    private var headerIcon: String {
        switch liveScope {
        case .pageType(let t): return t.icon ?? "folder"
        case .pageCollection(let c): return c.icon ?? "folder"
        case .itemType(let t): return t.icon ?? "tray"
        case .itemCollection(let c): return c.icon ?? "tray"
        default: return "slider.horizontal.3"
        }
    }

    /// `scope` re-resolved against the live `@Observable` managers so the header
    /// icon + title update the instant an edit commits. The captured `scope` is a
    /// value snapshot — reading it never re-renders on a manager change; reading
    /// the managers here registers the observation dependency (mirrors the detail
    /// views' `livePageType` / `liveCollection`). Falls back to the snapshot when
    /// the entity isn't resolvable (e.g. mid-delete).
    private var liveScope: ViewSettingsScope {
        switch scope {
        case .pageType(let t):
            return .pageType(pageTypeManager.types.first(where: { $0.id == t.id }) ?? t)
        case .pageCollection(let c):
            return .pageCollection(
                pageTypeManager.pageCollectionsByType[c.typeID]?.first(where: { $0.id == c.id }) ?? c)
        case .itemType(let t):
            return .itemType(itemTypeManager.types.first(where: { $0.id == t.id }) ?? t)
        case .itemCollection(let c):
            return .itemCollection(
                itemTypeManager.itemCollectionsByType[c.typeID]?.first(where: { $0.id == c.id }) ?? c)
        default:
            return scope
        }
    }

    /// Item-vs-page side derived from the scope (mirrors
    /// PropertyVisibilityPane's `side`). Drives which scopes get the live
    /// Templates pane vs. the muted placeholder.
    private enum SideKind { case pages, items }
    private var side: SideKind? {
        switch scope {
        case .pageType, .pageCollection: return .pages
        case .itemType, .itemCollection: return .items
        default: return nil
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
        case .pageType(let t):
            try? await pageTypeManager.updatePageTypeIcon(t, to: newIcon)
        case .pageCollection(let c):
            try? await pageTypeManager.updatePageCollectionIcon(c, to: newIcon)
        case .itemType(let t):
            try? await itemTypeManager.updateItemTypeIcon(t, to: newIcon)
        case .itemCollection(let c):
            try? await itemTypeManager.updateItemCollectionIcon(c, to: newIcon)
        default:
            break
        }
    }

    private func commitRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        defer { isRenaming = false }
        guard !trimmed.isEmpty, trimmed != headerTitle else { return }
        switch liveScope {
        case .pageType(let t):
            try? await pageTypeManager.renamePageType(t, to: trimmed)
        case .pageCollection(let c):
            try? await pageTypeManager.renamePageCollection(c, to: trimmed)
        case .itemType(let t):
            try? await itemTypeManager.renameItemType(t, to: trimmed)
        case .itemCollection(let c):
            try? await itemTypeManager.renameItemCollection(c, to: trimmed)
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
    #Preview("Storage menu — PageType") {
        StorageMenuRoot(
            scope: .pageType(
                PageType(
                    id: "01HPT", title: "Notes", icon: "note.text",
                    properties: [], views: [], modifiedAt: Date()
                )
            ),
            path: .constant([])
        )
    }
#endif
