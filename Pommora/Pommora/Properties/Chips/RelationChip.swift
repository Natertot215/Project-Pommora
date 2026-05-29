import SwiftUI

/// **The single rendering primitive for relation property values across every
/// Pommora surface.** Every surface that displays a relation value routes
/// through this primitive; adding a parallel rendering path duplicates it.
///
/// Consumers:
/// - `PropertyCellDisplay` (Table cells)
/// - `PropertyPanel` (single-entity property panel)
/// - `PropertiesPulldown` (planned property dropdown — not yet wired)
/// - `FrontmatterInspector` (page editor inspector)
/// - `ItemWindow` (item popover)
/// - `RelationPicker` (value-assignment popover rows)
/// - `LinkedFromDropdown` (Context-side reverse view — stub in v1; deferred)
///
/// **Data-model contract:** both `icon` and `title` resolve from the LINKED
/// target entity — the Page / Item / Task / Event / Context the chip references
/// — NEVER from the source-side relation property's icon/name. Resolution
/// happens at the consumer (via IndexQuery / the content managers); this
/// primitive receives pre-resolved `String` values and stays purely visual.
///
/// **Visual:** renders the target object's icon + title as plain text (no
/// pill / box / chrome) — interim treatment until a dedicated relation chip is
/// designed.
///
/// Stays at this path (`Properties/Chips/`). Do NOT move.
struct RelationChip: View {
    let icon: String
    let title: String

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
    }
}
