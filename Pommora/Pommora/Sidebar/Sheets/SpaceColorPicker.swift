import SwiftUI

/// 10-color palette grid for picking a SpaceColor: 9 Notion-palette hues + the
/// app accent rendered as a rainbow swatch. Laid out 5x2 (centered) since the
/// option count is now a clean multiple.
struct SpaceColorPicker: View {
    @Binding var color: SpaceColor

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
            ForEach(SpaceColor.allCases) { option in
                Button {
                    color = option
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
        }
    }

    @ViewBuilder
    private func swatch(for option: SpaceColor) -> some View {
        if option == .accent {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .red, .orange, .yellow, .green, .mint,
                            .teal, .blue, .indigo, .purple, .pink, .red
                        ]),
                        center: .center
                    )
                )
        } else {
            Circle().fill(option.swiftUIColor)
        }
    }
}
