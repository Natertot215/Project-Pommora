import SwiftUI

/// **The single rendering primitive for context-link property values across every
/// Pommora surface.** Every surface that displays a relation value routes
/// through this primitive; adding a parallel rendering path duplicates it.
///
/// Consumers:
/// - `PropertyCellDisplay` (Table cells)
/// - `PropertyPanel` (single-entity property panel)
/// - `PropertiesPulldown` (planned property dropdown — not yet wired)
/// - `FrontmatterInspector` (page editor inspector)
/// - `ContextPicker` (value-assignment popover rows)
/// - `LinkedFromDropdown` (Context-side reverse view — stub in v1; deferred)
///
/// **Data-model contract:** both `icon` and `title` resolve from the LINKED
/// target entity — the Page / Task / Event / Context the chip references
/// — NEVER from the source-side relation property's icon/name. Resolution
/// happens at the consumer (via IndexQuery / the content managers); this
/// primitive receives pre-resolved `String` values and stays purely visual.
///
/// **Visual:** the target's icon + title inside a standard-button-radius
/// rounded rectangle with a `.quinary` fill and a hairline separator stroke
/// (so it pops against standard surfaces) — distinct from `PropertyChip`'s
/// Capsule. Staged in the Component Library (Chips → Context Chip) per
/// Nathan's 2026-05-29 design.
///
/// Stays at this path (`Properties/Chips/`). Do NOT move.
struct ContextChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
