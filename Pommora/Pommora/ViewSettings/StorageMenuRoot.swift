import SwiftUI
import SymbolPicker

/// Root menu rendered inside the View Settings popover for the four storage
/// scopes (PageType / PageCollection / ItemType / ItemCollection).
///
/// Mirrors Notion's view-settings dropdown shape — header (icon + title,
/// both inline-editable for Type scopes) + a stack of pane rows. Two rows
/// are ACTIVE at v0.3.1 (Edit Properties + Property Visibility); the
/// remaining four (Layout / Filter / Sort / Group) render muted as
/// placeholder rows pointing at later v0.3.1.x patches.
///
/// Header inline edits (Type scopes only; Collection scopes get a display-
/// only header — Collections rename via the sidebar context menu, and they
/// don't carry their own icon at v0.3.1):
///   - Click icon → SymbolPicker sheet → commits via updatePageTypeIcon /
///     updateItemTypeIcon
///   - Click title → inline TextField → commits via renamePageType /
///     renameItemType on submit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, PUI.Pane.Header.paddingHorizontal)
                .padding(.top, PUI.Pane.Header.paddingTop)
                .padding(.bottom, PUI.Pane.Header.paddingBottom)

            Divider()

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
                mutedRow(icon: "doc.on.doc", title: "Templates")
                mutedRow(icon: "line.3.horizontal.decrease.circle", title: "Filter")
                mutedRow(icon: "square.stack.3d.down.right", title: "Group")
                mutedRow(icon: "arrow.up.arrow.down", title: "Sort")
            }
            .padding(.vertical, PUI.Spacing.xs)

            Spacer(minLength: 0)
        }
        .frame(width: PUI.Pane.width, height: PUI.Pane.height)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: PUI.Pane.Header.interSpacing) {
            iconAffordance
            titleAffordance
            Spacer(minLength: 0)
        }
    }

    /// Tappable icon for Type scopes (opens SymbolPicker), static Image for
    /// Collection scopes (Collections don't carry icons at v0.3.1).
    @ViewBuilder
    private var iconAffordance: some View {
        if isTypeScope {
            Button {
                iconPickerOpen = true
            } label: {
                Image(systemName: headerIcon)
                    .font(PUI.Icon.header)
                    .foregroundStyle(.primary)
                    .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change icon")
            .sheet(isPresented: $iconPickerOpen) {
                SymbolPicker(symbol: iconBinding)
            }
        } else {
            Image(systemName: headerIcon)
                .font(PUI.Icon.header)
                .foregroundStyle(.secondary)
                .frame(width: PUI.Icon.headerFrame, height: PUI.Icon.headerFrame)
        }
    }

    /// Tappable title for Type scopes (inline TextField rename), static
    /// Text for Collection scopes (rename via sidebar context menu).
    @ViewBuilder
    private var titleAffordance: some View {
        if isTypeScope {
            if isRenaming {
                TextField("Title", text: $renameDraft, onCommit: { Task { await commitRename() } })
                    .textFieldStyle(.roundedBorder)
                    .font(PUI.Typography.paneTitle)
                    .frame(maxWidth: 200)
                    .onAppear { renameDraft = headerTitle }
                    .onSubmit { Task { await commitRename() } }
            } else {
                Button {
                    renameDraft = headerTitle
                    isRenaming = true
                } label: {
                    Text(headerTitle)
                        .font(PUI.Typography.paneTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rename")
            }
        } else {
            Text(headerTitle)
                .font(PUI.Typography.paneTitle)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var isTypeScope: Bool {
        switch scope {
        case .pageType, .itemType: return true
        default: return false
        }
    }

    private var headerTitle: String {
        switch scope {
        case .pageType(let t): return t.title
        case .pageCollection(let c): return c.title
        case .itemType(let t): return t.title
        case .itemCollection(let c): return c.title
        default: return "View Settings"
        }
    }

    private var headerIcon: String {
        switch scope {
        case .pageType(let t): return t.icon ?? "folder"
        case .pageCollection: return "folder"  // PageCollection doesn't carry icon yet
        case .itemType(let t): return t.icon ?? "tray"
        case .itemCollection: return "tray"
        default: return "slider.horizontal.3"
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
        switch scope {
        case .pageType(let t):
            try? await pageTypeManager.updatePageTypeIcon(t, to: newIcon)
        case .itemType(let t):
            try? await itemTypeManager.updateItemTypeIcon(t, to: newIcon)
        default:
            break
        }
    }

    private func commitRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        defer { isRenaming = false }
        guard !trimmed.isEmpty, trimmed != headerTitle else { return }
        switch scope {
        case .pageType(let t):
            try? await pageTypeManager.renamePageType(t, to: trimmed)
        case .itemType(let t):
            try? await itemTypeManager.renameItemType(t, to: trimmed)
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
