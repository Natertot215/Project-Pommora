import SwiftUI

/// View Settings → Templates (ITEM scopes only).
///
/// Shell for the per-Type / per-Set template editor. T5.1 ships only the
/// route + pushed-pane chrome; the archetype picker (T5.2), the
/// `ItemWindowRenderer` mockup frame (T5.3), and scope wiring (T5.4) fill in
/// the body later. The route is payload-free — the pane derives its container
/// from its own `scope` (mirrors PropertyVisibilityPane's `containerID()` /
/// `side` pattern), so the route never carries an entity.
///
/// Chrome routed through shared `ViewSettingsPane` + `PaneHeader` + `PUI`
/// tokens, same as every other sub-pane.
struct ItemTemplatePane: View {
    let scope: ViewSettingsScope
    @Binding var path: [ViewSettingsRoute]

    var body: some View {
        ViewSettingsPane {
            PaneHeader(path: $path)
        } content: {
            content
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
            Text("Templates")
                .font(PUI.Typography.row)
                .foregroundStyle(.primary)
                .padding(.horizontal, PUI.Row.paddingHorizontal)
                .padding(.top, PUI.Row.paddingVertical)

            Text("Template editor")
                .font(PUI.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, PUI.Row.paddingHorizontal)
                .padding(.bottom, PUI.Row.paddingVertical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scope lookups
    //
    // Mirror PropertyVisibilityPane: extract the stable container ID + side
    // once from the scope, then (in later tasks) re-query the live manager for
    // every read. ITEM scopes only — the row that routes here is gated on
    // `.items` in StorageMenuRoot.

    private func containerID() -> String? {
        switch scope {
        case .itemType(let t): return t.id
        case .itemCollection(let c): return c.id
        default: return nil
        }
    }

    private func parentTypeID() -> String? {
        switch scope {
        case .itemType(let t): return t.id
        case .itemCollection(let c): return c.typeID
        default: return nil
        }
    }

    private enum SideKind { case items }
    private var side: SideKind? {
        switch scope {
        case .itemType, .itemCollection: return .items
        default: return nil
        }
    }
}

#if DEBUG
    #Preview("ItemTemplatePane — ItemType scope") {
        ItemTemplatePane(
            scope: .itemType(
                ItemType(
                    id: "01HIT", title: "Tasks", icon: "checklist",
                    properties: [], views: [], modifiedAt: Date()
                )
            ),
            path: .constant([.itemTemplate])
        )
    }
#endif
