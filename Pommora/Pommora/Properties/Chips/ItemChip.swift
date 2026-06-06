import SwiftUI

/// **The rendering primitive for resolved `{{Item}}` connections.** Mirrors
/// `ContextChip`'s `(icon, title)` shape but tuned for INLINE use inside the page
/// editor's body text, where it sits within denser typography than a property
/// cell. The page editor rasterizes this view to an `NSImage` and draws it at the
/// `{{ }}` token via the TextKit 2 layout-fragment overlay path (mirroring the
/// `.latexImage` inline render); the same primitive serves future non-inline item
/// surfaces (dropdown / panel).
///
/// **Design (Nathan, 2026-06-05):** Primary-label icon + title in body font,
/// Tertiary inside fill at 0.80 opacity, Secondary hairline outside stroke,
/// corner radius 6. Padding is intentionally tighter than `ContextChip` on BOTH
/// axes — reduced vertical so an inline chip stays within the line box (leaving
/// room for line breaks) and reduced horizontal (label↔border) for the dense
/// inline context.
///
/// **Data-model contract:** `icon` + `title` resolve from the LINKED Item (via
/// `IndexQuery` / the item content manager) — never from the source side. This
/// primitive receives pre-resolved `String` values and stays purely visual.
///
/// Stays at this path (`Properties/Chips/`), beside `ContextChip`. Do NOT move.
struct ItemChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(.primary)
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .font(.body)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.tertiary.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.secondary, lineWidth: 0.5)
        )
    }
}
