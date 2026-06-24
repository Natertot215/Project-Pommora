import SwiftUI

/// The Views dropdown popover content: one row per saved view on the container,
/// a footer "New View" action, and an inline type-switch expansion per row.
///
/// Resolves the container's views LIVE off `PageCollectionManager` by `containerID`
/// (PageCollection or PageCollection — the same dual lookup the panes use), so CRUD
/// edits reflect immediately. Active-view switching routes through
/// `ActiveViewStore.setActive`.
///
/// Styled with the shared `.chipDropdownPanel()` Liquid-Glass surface and a
/// fixed 280pt width.
struct ViewsPanel: View {
    let containerID: String
    /// Dismisses the hosting popover after an active-view switch.
    let onDismiss: () -> Void

    @Environment(PageCollectionManager.self) private var collectionManager
    @Environment(ActiveViewStore.self) private var activeViewStore

    @State private var commitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(views) { view in
                viewRow(view)
            }

            Divider().padding(.vertical, PUI.Spacing.xs)

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
        .padding(.vertical, PUI.Spacing.sm)
        .frame(width: 280)
        .focusable()
        .onMoveCommand { direction in stepActive(direction) }
        // Keep arrow-key nav but drop the blue focus ring/selection wash.
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func viewRow(_ view: SavedView) -> some View {
        ViewsPanelRow(
            view: view,
            isActive: view.id == activeID,
            onSelect: {
                activeViewStore.setActive(view.id, for: containerID)
                onDismiss()
            },
            onSwitchType: { type in Task { await switchType(view.id, to: type) } },
            onPickIcon: { icon in Task { await setIcon(view.id, to: icon) } },
            onRename: { name in Task { await rename(view.id, to: name) } },
            onDuplicate: { Task { await duplicate(view.id) } },
            onDelete: { Task { await delete(view.id) } },
            canDelete: views.count > 1
        )
    }

    // MARK: - Live container resolution

    private var views: [SavedView] {
        collectionManager.views(in: containerID)
    }

    private var activeID: String? {
        activeViewStore.resolvedActiveView(in: containerID, manager: collectionManager)?.id
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
        do { _ = try await collectionManager.addView(type: .table, to: containerID) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func duplicate(_ viewID: String) async {
        do { _ = try await collectionManager.duplicateView(viewID, in: containerID) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func delete(_ viewID: String) async {
        do { try await collectionManager.deleteView(viewID, in: containerID) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func rename(_ viewID: String, to name: String) async {
        do { try await collectionManager.renameView(viewID, in: containerID, to: name) } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func setIcon(_ viewID: String, to icon: String?) async {
        do {
            try await collectionManager.updateView(viewID, in: containerID) { $0.icon = icon }
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }

    private func switchType(_ viewID: String, to type: ViewType) async {
        do {
            try await collectionManager.updateView(viewID, in: containerID) { v in
                v.type = type
                // Gallery needs a card size; mint the default when switching in.
                if type == .gallery, v.cardSize == nil { v.cardSize = .medium }
            }
        } catch {
            commitError = PropertyEditorErrorMessage.string(for: error)
        }
    }
}

// MARK: - (Type switching now lives in each row's chevron menu — see ViewsPanelRow.)
