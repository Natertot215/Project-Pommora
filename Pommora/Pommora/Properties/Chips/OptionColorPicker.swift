import SwiftUI

/// Compact 5×2 swatch grid for picking a `PropertyChipColor` value, plus a
/// separate "No color" affordance that clears the selection back to `nil`.
///
/// Used by `EditOptionPane` (Task 11b) for per-option color picking on
/// Select / Multi-Select / Status options. The 10 pickable swatches come
/// from `PropertyChipColor.selectablePalette` (excludes `.default` and
/// `.accent` — see PropertyChipColor doc for why).
///
/// Selection semantics:
/// - Tapping a swatch writes that color value to the bound optional.
/// - Tapping "No color" writes `nil` (renders as `.default` downstream).
/// - The currently-selected swatch shows a thin ring; "No color" shows the
///   same ring when the bound value is `nil`.
struct OptionColorPicker: View {
    @Binding var selection: PropertyChipColor?

    private let swatchSize: CGFloat = 22
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 5×2 grid of 10 selectable colors.
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(swatchSize), spacing: spacing), count: 5),
                spacing: spacing
            ) {
                ForEach(PropertyChipColor.selectablePalette, id: \.self) { color in
                    swatch(for: color)
                }
            }

            // Separate "No color" affordance — writes nil to the binding.
            Button {
                selection = nil
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color(.separatorColor), lineWidth: 1)
                            .frame(width: swatchSize, height: swatchSize)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .overlay(selectionRing(isOn: selection == nil))
                    Text("No color")
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No color")
        }
    }

    @ViewBuilder
    private func swatch(for color: PropertyChipColor) -> some View {
        Button {
            selection = color
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: swatchSize, height: swatchSize)
                .overlay(selectionRing(isOn: selection == color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
    }

    @ViewBuilder
    private func selectionRing(isOn: Bool) -> some View {
        if isOn {
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: swatchSize + 4, height: swatchSize + 4)
        }
    }
}
