import SwiftUI

/// Floating chip used as the drag preview while a row is being dragged
/// (v0.2.8.0). Finder-aesthetic: icon + title on a translucent material card,
/// not the default opaque white card SwiftUI uses when you don't supply a
/// custom preview. Matches the visual weight of `SelectionChrome` so the
/// dragged row reads as the same UI element travelling through the sidebar.
struct SidebarDragPreview: View {
    let symbol: String
    let title: String
    let accent: Color?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accent ?? .primary)
                .frame(width: 16, height: 16, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}
