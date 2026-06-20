import SwiftUI

struct MultiSelectChips: View {
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
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

/// Simple flow layout — wraps chips to multiple lines.
/// SwiftUI Layout protocol (macOS 13+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > containerWidth {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth - spacing)
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth - spacing)
        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
