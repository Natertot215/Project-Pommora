import SwiftUI

/// 10-swatch palette grid: 9 Notion-palette hues + a rainbow "no color"
/// swatch that clears the selection (sets binding to nil). `.blue` renders
/// as the brand accent (per `AreaColor.blue`'s mapping to
/// `Color.accentColor`). Laid out 5x2 (centered).
struct AreaColorPicker: View {
    @Binding var color: AreaColor?

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5)

    /// Hues shown in the grid. The rainbow "no color" swatch is appended
    /// separately so the click handler can map it to `nil` without
    /// special-casing the `AreaColor` enum.
    private static let hues: [AreaColor] = [
        .gray, .brown, .orange, .yellow, .green,
        .blue, .purple, .pink, .red,
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
            ForEach(Self.hues) { option in
                Button {
                    color = (color == option) ? nil : option
                } label: {
                    swatch(for: option)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: color == option ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
            }

            Button {
                color = nil
            } label: {
                rainbowSwatch
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: color == nil ? 2 : 0)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No color")
        }
    }

    @ViewBuilder
    private func swatch(for option: AreaColor) -> some View {
        Circle().fill(option.swiftUIColor)
    }

    private var rainbowSwatch: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .red, .orange, .yellow, .green, .mint,
                        .teal, .blue, .indigo, .purple, .pink, .red,
                    ]),
                    center: .center
                )
            )
    }
}
