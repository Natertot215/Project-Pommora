import SwiftUI

/// The atomic visual primitive for a rendered property option — a `Capsule`
/// with a colored fill + tinted label (pill) or a single SF Symbol (chip).
struct PropertyChip: View {
    let content: Content
    let color: PropertyChipColor
    var size: Size = .standard

    /// Context sizing. `.standard` is the Figma spec (panel, dropdown);
    /// `.compact` fits a `Table` row without inflating it (also used by table
    /// group-header pills, which match the in-row chip).
    enum Size: Sendable {
        case standard
        case compact

        var pillFont: Font {
            switch self {
            case .standard: .system(size: 12, weight: .semibold)
            case .compact: .system(size: 11, weight: .semibold)
            }
        }
        var iconFont: Font {
            switch self {
            case .standard: .system(size: 11, weight: .semibold)
            case .compact: .system(size: 10, weight: .semibold)
            }
        }
        var pillMinWidth: CGFloat { self == .standard ? 50 : 40 }
        var minHeight: CGFloat { self == .standard ? 20 : 16 }
        var iconMinWidth: CGFloat { self == .standard ? 32 : 26 }
        var hPadding: CGFloat { self == .standard ? 6 : 5 }
    }

    /// Discriminated content — `.pill` carries a text Label, `.chip` carries an
    /// SF Symbol icon name. The variant is implicit from the content type.
    enum Content: Hashable, Sendable {
        case pill(label: String)
        case chip(icon: String)  // SF Symbol name
    }

    // MARK: Convenience initializers

    init(label: String, color: PropertyChipColor, size: Size = .standard) {
        self.content = .pill(label: label)
        self.color = color
        self.size = size
    }

    init(icon: String, color: PropertyChipColor, size: Size = .standard) {
        self.content = .chip(icon: icon)
        self.color = color
        self.size = size
    }

    init(content: Content, color: PropertyChipColor, size: Size = .standard) {
        self.content = content
        self.color = color
        self.size = size
    }

    // MARK: Body

    var body: some View {
        switch content {
        case .pill(let label): pillBody(label: label)
        case .chip(let icon): chipBody(icon: icon)
        }
    }

    private func pillBody(label: String) -> some View {
        let base = color.swiftUIColor
        return Text(label)
            .font(size.pillFont)
            .lineSpacing(3)
            .foregroundStyle(PUI.Tint.label(base))
            .padding(.horizontal, size.hPadding)
            .frame(minWidth: size.pillMinWidth, minHeight: size.minHeight)
            .coloredChip(base, in: Capsule())
    }

    private func chipBody(icon: String) -> some View {
        let base = color.swiftUIColor
        return Image(systemName: icon)
            .font(size.iconFont)
            .foregroundStyle(PUI.Tint.label(base))
            .frame(minWidth: size.iconMinWidth, minHeight: size.minHeight)
            .coloredChip(base, in: Capsule())
    }
}
