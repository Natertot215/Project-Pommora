import SwiftUI

/// Bottom stats bar for the Page editor.
///
/// Collapsed state (a tiny up-chevron) is rendered by the host as a
/// `.bottomTrailing` overlay so it reserves no layout space. This view is the
/// *expanded* bar: `Vault / Collection` on the left, `Lines · Words ·
/// Characters` on the right, with a down-chevron above the counts that is
/// shown for 3s after opening, then goes hover-only (mirrors the heading-fold
/// chevron's hover-reveal). The host owns `isExpanded` + `stats`.
struct PageStatsBar: View {
    @Binding var isExpanded: Bool
    let breadcrumb: String
    let stats: PageTextStats

    /// True for the first 3 s after opening, then false — after which the
    /// down-chevron is gated on `hovering`. Reset each time the bar appears.
    @State private var collapseAffordanceForced = false
    @State private var hovering = false

    private var showCollapseChevron: Bool { collapseAffordanceForced || hovering }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded = false }
            } label: {
                Image(systemName: "chevron.compact.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(showCollapseChevron ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showCollapseChevron)
            .accessibilityLabel("Hide statistics")

            HStack(spacing: 0) {
                Text(breadcrumb)
                Spacer(minLength: 12)
                Text(countsAttributed)
                    .help("Lines · Words · Characters")
            }
            .font(PUI.Typography.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task {
            collapseAffordanceForced = true
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { collapseAffordanceForced = false }
        }
    }

    /// "12 · 340 · 1,890" — numbers inherit the bar's `.secondary` tint; the
    /// `·` separators are a touch fainter (tertiary label).
    private var countsAttributed: AttributedString {
        var separator = AttributedString(" · ")
        separator.foregroundColor = Color(nsColor: .tertiaryLabelColor)

        var result = AttributedString(stats.lines.formatted())
        result.append(separator)
        result.append(AttributedString(stats.words.formatted()))
        result.append(separator)
        result.append(AttributedString(stats.characters.formatted()))
        return result
    }
}
