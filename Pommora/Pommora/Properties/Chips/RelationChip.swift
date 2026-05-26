import SwiftUI

/// Rendering primitive for Relation property values.
///
/// Distinct from `PropertyChip`'s Capsule shape — RelationChip uses a
/// RoundedRectangle (cornerRadius 4) so relation cells read as a different
/// visual class from Select/Multi/Status pills. Default-grey fill across
/// all relations (no per-property color at v0.3.1; per-property override
/// deferred).
///
/// Takes a pre-resolved `icon: String` (SF Symbol of the target entity
/// kind — `doc.text` for pages, `tray` for items, etc.) + the target's
/// current `title: String`. Lookup of those values from a relation
/// PropertyValue ULID is the caller's responsibility (IndexQuery /
/// PageContentManager / etc.) — keeps this primitive purely visual.
///
/// Used by `PropertyCellDisplay` for Relation column rendering.
struct RelationChip: View {
    let icon: String
    let title: String

    private let cornerRadius: CGFloat = 4
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 3

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.tertiarySystemFill))
        )
    }
}
