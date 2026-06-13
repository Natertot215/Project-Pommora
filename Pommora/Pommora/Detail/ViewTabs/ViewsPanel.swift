import SwiftUI

/// The Views dropdown popover content: one row per saved view on the container,
/// a footer "New View" action, and an inline type-switch expansion per row.
///
/// Resolves the container's views LIVE off `PageTypeManager` by `containerID`
/// (PageType or PageCollection — the same dual lookup the panes use), so CRUD
/// edits reflect immediately. Active-view switching routes through
/// `ActiveViewStore.setActive`.
///
/// Styled with the shared `.chipDropdownPanel()` Liquid-Glass surface and a
/// fixed 280pt width.
struct ViewsPanel: View {
    let containerID: String
    /// Dismisses the hosting popover after an active-view switch.
    let onDismiss: () -> Void

    @Environment(PageTypeManager.self) private var pageTypeManager
    @Environment(ActiveViewStore.self) private var activeViewStore

    @State private var expandedTypeViewID: String?
    @State private var iconPickerViewID: String?
    @State private var commitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(views) { view in
                viewRow(view)
                if expandedTypeViewID == view.id {
                    ViewTypeSwitchRow(current: view.type) { newType in
                        Task { await switchType(view.id, to: newType) }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            Button(action: { Task { await addView() } }) {
                HStack(spacing: PUI.Row.interSpacing) {
                    Image(systemName: "plus")
                        .font(PUI.Icon.leading)
                        .frame(width: PUI.Icon.leadingFrame)
                    Text("New View")
                        .font(PUI.Typography.row)
                    Spacer()
                }
                .padding(.horizontal, PUI.Row.paddingHorizontal)
                .padding(.vertical, PUI.Row.paddingVertical)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let err = commitError {
                Text(err)
                    .font(PUI.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, PUI.Row.paddingHorizontal)
                    .padding(.bottom, PUI.Row.paddingVertical)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .focusable()
        .onMoveCommand { direction in stepActive(direction) }
        .chipDropdownPanel()
        .sheet(item: iconPickerSheet) { sheet in
            if case .editIcon(let target) = sheet {
                IconPickerSheet(target: target)
            }
        }
    }

    @ViewBuilder
    private func viewRow(_ view: SavedView) -> some View {
        ViewsPanelRow(
            view: view,
            isActive: view.id == activeID,
            isTypeExpanded: expandedTypeViewID == view.id,
            onSelect: {
                activeViewStore.setActive(view.id, for: containerID)
                onDismiss()
            },
            onToggleType: {
                expandedTypeViewID = expandedTypeViewID == view.id ? nil : view.id
            },
            onPickIcon: { iconPickerViewID = view.id },
            onRename: { name in Task { await rename(view.id, to: name) } },
            onDuplicate: { Task { await duplicate(view.id) } },
            onDelete: { Task { await delete(view.id) } },
            canDelete: views.count > 1
        )
        .focusable()
    }

    // MARK: - Live container resolution

    private var views: [SavedView] {
        pageTypeManager.views(in: containerID)
    }

    private var activeID: String? {
        activeViewStore.resolvedActiveView(in: containerID, manager: pageTypeManager)?.id
    }

    /// Wraps the in-flight icon-picker view ID as the `Identifiable`
    /// `SidebarSheet` the icon picker is presented through.
    private var iconPickerSheet: Binding<SidebarSheet?> {
        Binding(
            get: {
                iconPickerViewID.map {
                    .editIcon(.savedView(viewID: $0, containerID: containerID))
                }
            },
            set: { newValue in
                if newValue == nil { iconPickerViewID = nil }
            }
        )
    }

    /// Up/down arrow moves the active view to the previous/next row.
    private func stepActive(_ direction: MoveCommandDirection) {
        let list = views
        guard let current = list.firstIndex(where: { $0.id == activeID }) else { return }
        let next: Int
        switch direction {
        case .up: next = max(0, current - 1)
        case .down: next = min(list.count - 1, current + 1)
        default: return
        }
        guard next != current else { return }
        activeViewStore.setActive(list[next].id, for: containerID)
    }

    // MARK: - CRUD bridges

    private func addView() async {
        do { _ = try await pageTypeManager.addView(type: .table, to: containerID) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func duplicate(_ viewID: String) async {
        do { _ = try await pageTypeManager.duplicateView(viewID, in: containerID) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func delete(_ viewID: String) async {
        do { try await pageTypeManager.deleteView(viewID, in: containerID) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func rename(_ viewID: String, to name: String) async {
        do { try await pageTypeManager.renameView(viewID, in: containerID, to: name) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func switchType(_ viewID: String, to type: ViewType) async {
        expandedTypeViewID = nil
        do {
            try await pageTypeManager.updateView(viewID, in: containerID) { v in
                v.type = type
                // Gallery needs a card size; mint the default when switching in.
                if type == .gallery, v.cardSize == nil { v.cardSize = .medium }
            }
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }
}

// MARK: - Inline type switch

/// Inline expansion under a view row offering the renderer types. Implemented
/// types (Table / Gallery) are active; the rest render muted/disabled. Modeled
/// over `ViewType.allCases` so every case is compiler-enforced.
private struct ViewTypeSwitchRow: View {
    let current: ViewType
    let onSelect: (ViewType) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ViewType.allCases, id: \.self) { type in
                Button(action: { onSelect(type) }) {
                    Label(type.displayName, systemImage: type.defaultIcon)
                        .labelStyle(.iconOnly)
                        .font(PUI.Icon.leading)
                        .frame(width: 28, height: 24)
                        .foregroundStyle(type == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .opacity(type.isImplemented ? 1 : 0.35)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!type.isImplemented)
                .help(type.displayName)
            }
            Spacer()
        }
        .padding(.horizontal, PUI.Row.paddingHorizontal)
        .padding(.vertical, 4)
    }
}
