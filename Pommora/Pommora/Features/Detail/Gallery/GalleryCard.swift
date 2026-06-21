import Nuke
import NukeUI
import SwiftUI

/// One gallery card. Renders (top→bottom): an optional COVER area (only when
/// `showCover`), a header (icon + title), and the three property zones from
/// `GalleryCardZones.partition` — chips / meta / links — each reusing the
/// table's `PropertyCellEditor` so values stay assignable + removable on the
/// card.
///
/// Interactions: single click selects; double-click the TITLE renames inline
/// (via `onRename`); double-click elsewhere opens (via `onOpen`); icon click
/// edits the icon (`onEditIcon`); right-click the card = page menu; right-click
/// the COVER area (when visible) = Set / Change / Remove Cover (`onCoverMenu`).
/// Per-card hover applies a subtle scale + shadow.
struct GalleryCard: View {
    let item: ViewItem
    let view: SavedView
    let schema: [PropertyDefinition]
    let nexus: Nexus
    let index: PommoraIndex?
    let isSelected: Bool

    let relationResolver: (String) -> (icon: String, title: String)?
    let commit: (PropertyDefinition, PropertyValue?) -> Void
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRename: () -> Void
    let onEditIcon: () -> Void
    let pageMenu: () -> AnyView
    /// Cover-area context menu (Set / Change / Remove). Nil when covers hidden.
    let coverMenu: (() -> AnyView)?

    @State private var isHovering: Bool = false

    private var zones: (chips: [PropertyDefinition], meta: [PropertyDefinition], links: [PropertyDefinition]) {
        GalleryCardZones.partition(view: view, schema: schema)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.md) {
            if view.showCover == true {
                coverArea
            }
            header
            zoneStack
        }
        .padding(PUI.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: PUI.Radius.gallery)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PUI.Radius.gallery)
                .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isHovering ? 1.015 : 1)
        .shadow(color: .black.opacity(isHovering ? 0.18 : 0.06), radius: isHovering ? 8 : 3, y: 2)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: PUI.Radius.gallery))
        .onHover { isHovering = $0 }
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .contextMenu { pageMenu() }
    }

    // MARK: - Cover

    @ViewBuilder
    private var coverArea: some View {
        let area = Group {
            if let path = item.page.frontmatter.cover {
                LazyImage(request: coverRequest(path)) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color(.quaternarySystemFill)
                    }
                }
            } else {
                // Empty fill when no cover set (showCover still reserves the area).
                Color(.quaternarySystemFill)
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.card))

        if let coverMenu {
            area.contextMenu { coverMenu() }
        } else {
            area
        }
    }

    private func coverRequest(_ path: String) -> ImageRequest {
        let url = AssetURLResolver.fileURL(forRelativePath: path, in: nexus)
        return ImageRequest(
            url: url,
            processors: [
                ImageProcessors.Resize(
                    size: CGSize(width: 280, height: 220), unit: .points,
                    contentMode: .aspectFill, crop: true)
            ]
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: PUI.Spacing.sm) {
            Button {
                onEditIcon()
            } label: {
                PageIconGlyph(icon: item.page.frontmatter.icon)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text(item.page.title)
                .font(.headline)
                .lineLimit(2)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded { onRename() })

            Spacer(minLength: 0)

            if let label = item.setLabel {
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, PUI.Spacing.sm)
                    .padding(.vertical, PUI.Spacing.xxs)
                    .background(Capsule().fill(Color(.quaternarySystemFill)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Zones

    @ViewBuilder
    private var zoneStack: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
            ForEach(zones.chips, id: \.id) { def in
                GalleryZoneCell(
                    item: item, definition: def, index: index, relationResolver: relationResolver, commit: commit)
            }
            ForEach(zones.meta, id: \.id) { def in
                GalleryZoneCell(
                    item: item, definition: def, index: index, relationResolver: relationResolver, commit: commit)
            }
            ForEach(zones.links, id: \.id) { def in
                GalleryZoneCell(
                    item: item, definition: def, index: index, relationResolver: relationResolver, commit: commit)
            }
        }
    }
}

/// One property row inside a gallery card, reusing the table's
/// `PropertyCellEditor` (popover commit-on-dismiss). Isolated as a plain-value
/// sub-view — keeps the relation-vs-scalar value selection out of the parent
/// `@ViewBuilder`, avoiding GRDB `String` overload ambiguity.
private struct GalleryZoneCell: View {
    let item: ViewItem
    let definition: PropertyDefinition
    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let commit: (PropertyDefinition, PropertyValue?) -> Void

    var body: some View {
        HStack(spacing: PUI.Spacing.sm) {
            Image(systemName: definition.displayIcon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            PropertyCellEditor(
                definition: definition,
                value: item.page.frontmatter.cellValue(for: definition),
                relationResolver: relationResolver,
                commit: { commit(definition, $0) },
                index: index
            )
        }
        .font(.caption)
    }
}
