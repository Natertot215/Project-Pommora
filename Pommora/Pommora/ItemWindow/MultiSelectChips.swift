import SwiftUI

struct MultiSelectChips: View {
    let options: [String]
    @Binding var selected: [String]
    let allowsAddingOptions: Bool

    @State private var draftNew: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    chip(for: option)
                }
                if allowsAddingOptions {
                    addButton
                }
            }
        }
    }

    private func chip(for option: String) -> some View {
        let isOn = selected.contains(option)
        return Button {
            toggle(option)
        } label: {
            Text(option)
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isOn ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        HStack(spacing: 4) {
            TextField("Add option", text: $draftNew)
                .textFieldStyle(.plain)
                .frame(maxWidth: 100)
                .onSubmit {
                    let trimmed = draftNew.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !selected.contains(trimmed) else { return }
                    selected.append(trimmed)
                    draftNew = ""
                }
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.gray.opacity(0.08)))
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
