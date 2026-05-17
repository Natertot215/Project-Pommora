import SwiftUI

/// Inline 9-color grid for picking a SpaceColor. Used inside sheets and pickers.
struct SpaceColorPicker: View {
    @Binding var color: SpaceColor

    private let columns = [GridItem(.adaptive(minimum: 32), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SpaceColor.allCases) { option in
                Button {
                    color = option
                } label: {
                    Circle()
                        .fill(option.swiftUIColor)
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
}
