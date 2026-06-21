import SwiftUI

struct MultiSelectChips: View {
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PUI.Spacing.sm) {
            FlowLayout(spacing: PUI.Spacing.sm) {
                ForEach(options, id: \.self) { option in
                    chip(for: option)
                }
            }
        }
    }

    private func chip(for option: String) -> some View {
        let isOn = selected.contains(option)
        let label = Text(option)
            .font(.callout)
            .foregroundStyle(isOn ? PUI.Tint.label(PUI.Colors.accent) : PUI.Colors.labelPrimary)
            .padding(.horizontal, PUI.Chip.tagPaddingHorizontal)
            .padding(.vertical, PUI.Chip.tagPaddingVertical)
        return Button {
            toggle(option)
        } label: {
            if isOn {
                label.coloredChip(PUI.Colors.accent, in: Capsule())
            } else {
                label.background(Capsule().fill(PUI.Tint.quaternary(PUI.Colors.chipBase)))
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ option: String) {
        if let i = selected.firstIndex(of: option) {
            selected.remove(at: i)
        } else {
            selected.append(option)
        }
    }
}
