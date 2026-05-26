import SwiftUI

/// The atomic visual primitive used everywhere a property option is rendered.
/// Pure composition of `Capsule` / `Text` / `Image` — no re-styling of Apple
/// controls. Used across Item Window, Properties Pulldown, FrontmatterInspector,
/// and future gallery / board / table cell views.
///
/// Mirrors the Figma spec verbatim:
/// - **Pill** variant: 50pt × 20pt logical size, text Label (6pt horizontal padding)
/// - **Chip** variant: 32pt × 20pt logical size, SF Symbol icon centered
/// - Both: Capsule background (auto-max corner radius == Figma `rounded-[100px]`)
/// - Font (Pill): SF Pro Semibold 12pt with 15pt line height (Callout/Emphasized)
/// - Foreground: pure white
///
/// **All drop shadows REMOVED 2026-05-25 per Nathan's directive** — flat
/// chip aesthetic. Text-emboss highlight method removed alongside; if the
/// white-on-bright-fill legibility needs recovery later, do it via a
/// non-shadow technique (e.g. blending mode, slight luminance boost).
struct PropertyChip: View {
    let content: Content
    let color: PropertyChipColor

    /// Discriminated content — `.pill` carries a text Label, `.chip` carries an
    /// SF Symbol icon name. The variant is implicit from the content type.
    enum Content: Hashable, Sendable {
        case pill(label: String)
        case chip(icon: String)  // SF Symbol name
    }

    // MARK: Convenience initializers

    init(label: String, color: PropertyChipColor) {
        self.content = .pill(label: label)
        self.color = color
    }

    init(icon: String, color: PropertyChipColor) {
        self.content = .chip(icon: icon)
        self.color = color
    }

    init(content: Content, color: PropertyChipColor) {
        self.content = content
        self.color = color
    }

    // MARK: Body

    var body: some View {
        switch content {
        case .pill(let label): pillBody(label: label)
        case .chip(let icon): chipBody(icon: icon)
        }
    }

    private func pillBody(label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .lineSpacing(3)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 50, minHeight: 20)
            .background(Capsule().fill(color.swiftUIColor))
    }

    private func chipBody(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(minWidth: 32, minHeight: 20)
            .background(Capsule().fill(color.swiftUIColor))
    }
}
