import SwiftUI

/// Root menu rendered inside the View Settings popover for the four storage
/// scopes (PageType / PageCollection / ItemType / ItemCollection).
///
/// Mirrors Notion's view-settings dropdown shape — header label + a stack of
/// pane rows. Two rows are ACTIVE at v0.3.1 (Edit Properties + Property
/// Visibility); the remaining four (Layout / Filter / Sort / Group) render
/// muted as placeholder rows pointing at later v0.3.1.x patches.
///
/// Push behavior lives at the popover level — this view appends routes to
/// the `path` binding passed from the popover. The binding form keeps the
/// menu purely declarative + lets the popover own all NavigationStack state.
struct StorageMenuRoot: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

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
                mutedRow(icon: "rectangle.3.group", title: "Layout", note: "v0.5.0")
                mutedRow(icon: "line.3.horizontal.decrease.circle", title: "Filter", note: "v0.3.1.3")
                mutedRow(icon: "arrow.up.arrow.down", title: "Sort", note: "v0.3.1.2")
                mutedRow(icon: "square.stack.3d.down.right", title: "Group", note: "v0.3.1.4")
            }
            .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .frame(width: 300, height: 360)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
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
        case .pageCollection(let c): return "folder"  // PageCollection doesn't carry icon yet
        case .itemType(let t): return t.icon ?? "tray"
        case .itemCollection: return "tray"
        default: return "slider.horizontal.3"
        }
    }

    @ViewBuilder
    private func activeRow(icon: String, title: String, route: ViewSettingsRoute) -> some View {
        Button {
            path.append(route)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 18)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mutedRow(icon: String, title: String, note: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
            Text(title)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(note)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
