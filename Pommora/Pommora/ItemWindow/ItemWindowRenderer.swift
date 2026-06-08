import MarkdownPM
import SwiftUI

/// The single live Item-Window renderer. It currently draws a clean display-only
/// stub — the Item's icon + title (`header`), a read-only body (`stubBody`), and a
/// breadcrumb footer — nothing else. This stub is the bedrock the interactive
/// zones will be built onto; the renderer reads the resolved `Item` +
/// `ItemTemplateConfig` + Type schema and performs NO CRUD on the live path.
///
/// The reorder/partition helpers below (`partition`, `reorderPromoted`) are pure,
/// unit-tested, and retained for the zone rework even though no production caller
/// references them yet.
struct ItemWindowRenderer: View {
    let item: Item
    let template: ItemTemplateConfig
    let itemType: ItemType
    let collection: ItemCollection?

    // MARK: - Promoted / overflow partition (pure)

    /// Splits the full ordered property-id list into the promoted set (main panel,
    /// in promoted order) and the overflow remainder, GUARANTEED disjoint — no id
    /// appears in both region (resolves the legacy double-render, Fix Log #10).
    /// Promoted ids not present in `all` are ignored; overflow preserves `all`'s
    /// order minus the promoted ids.
    ///
    /// Pure value code OUTSIDE any `@ViewBuilder` body, so `Array.contains` is safe
    /// here (quirk #12's GRDB String-overload ambiguity only bites inside views).
    static func partition(all: [String], promoted: [String]) -> (main: [String], overflow: [String]) {
        let promotedSet = Set(promoted)
        let main = promoted.filter { all.contains($0) }  // promoted order, real ids only
        let overflow = all.filter { !promotedSet.contains($0) }  // remainder, original order
        return (main, overflow)
    }

    // MARK: - Edit-mode reorder (pure, T3.5)

    /// Reorders the promoted list by ID (via `PropertyIDReorder.move`), PRESERVING
    /// each `PromotedProperty` entry (its per-property `display`). The edit-mode
    /// drag handler routes through this. Pure value code OUTSIDE any `@ViewBuilder`
    /// body, so it stays unit-testable without a SwiftUI host (quirk #12-safe).
    static func reorderPromoted(
        _ promoted: [PromotedProperty], moving: String, onto target: String
    ) -> [PromotedProperty] {
        let newIDOrder = PropertyIDReorder.move(promoted.map(\.id), moving: moving, onto: target)
        return newIDOrder.compactMap { id in promoted.first { $0.id == id } }
    }

    // MARK: - Body

    /// Two-column card scaffold (Phase D0): the main column (header + body) on the
    /// left, the inspector column on the right, separated by a vertical divider —
    /// the whole card framed to the fixed Item-Window dimensions. Both columns are
    /// always shown here; the show/hide toggle arrives with the view-model (D1/D7).
    /// The footer spans the full card width as a bottom inset.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mainColumn
            Divider()
            inspectorColumn
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                footer
            }
            .background(.bar)
        }
        .frame(width: PUI.ItemWindow.totalWidth, height: PUI.ItemWindow.height)
    }

    // MARK: - Main column (header + body)

    /// Left column — the existing scrolling stub (icon + title header, read-only
    /// body), flexing to fill the space left of the inspector.
    private var mainColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PUI.Spacing.xl) {
                // Live window — a clean display-only stub: icon + title + body
                // + footer, nothing else. The zone framework builds onto this
                // bedrock.
                header
                stubBody
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Inspector column

    /// Right column — fixed-width inspector. Empty stub for now; D5 fills it with
    /// the inspector zone content.
    private var inspectorColumn: some View {
        Color.clear
            .frame(width: PUI.ItemWindow.inspectorWidth)
            .frame(maxHeight: .infinity)
    }

    // MARK: - 1. Header (icon + title)

    /// Display-only header: the Item's icon (falling back to the Type's) + its
    /// title. The live window is a display stub, so nothing edits here.
    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: item.icon ?? itemType.icon ?? "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Live-window body stub

    /// The live window's display-only body: the Item's description rendered with
    /// the read-only MarkdownPM editor (`isEditable: false` — no caret, no commit
    /// path). This is the stub bedrock the zone framework replaces; the editable
    /// editor + cap counter + save machinery were retired with the display stub.
    private var stubBody: some View {
        MarkdownPMEditor(
            text: .constant(item.description),
            configuration: MarkdownEditorConfig.pommora(verticalInset: 0),
            fontName: "SF Pro Text",
            fontSize: 15,
            documentId: item.id,
            isEditable: false
        )
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    // MARK: - Footer (breadcrumb + options control)

    private var footer: some View {
        DetailFooterBar(crumbs: footerCrumbs) {
            Menu {
                // Template / view options land here (zone-framework rework).
                Text("Options")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var footerCrumbs: [FooterCrumb] {
        var crumbs = [FooterCrumb(title: itemType.title)]
        if let collection {
            crumbs.append(FooterCrumb(title: collection.title))
        }
        return crumbs
    }
}
