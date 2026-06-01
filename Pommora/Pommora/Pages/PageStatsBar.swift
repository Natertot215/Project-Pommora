import SwiftUI

/// The expanded Page stats row: a `Vault › Collection › Page` breadcrumb
/// (Finder-style `›` separators) on the left, `Lines · Words · Characters` on
/// the right. The toggle chevron lives as an editor overlay in `PageEditorView`
/// (outside this bar) so the bar's height stays minimal.
struct PageStatsBar: View {
    /// Breadcrumb component titles, outermost first: [Vault, Collection?, Page].
    let breadcrumb: [String]
    let stats: PageTextStats

    var body: some View {
        HStack(spacing: 0) {
            // "Vault › Collection › Page", Finder-style.
            Text(joined(breadcrumb, separator: " › "))
            Spacer(minLength: PUI.Spacing.xl)
            // "12 · 340 · 1,890".
            Text(joined(countComponents, separator: " · "))
                .help("Lines · Words · Characters")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, PUI.Spacing.xl)
        .padding(.vertical, PUI.Spacing.sm)
        .frame(maxWidth: .infinity)
    }

    private var countComponents: [String] {
        [stats.lines, stats.words, stats.characters].map { $0.formatted() }
    }

    /// Joins `parts` with a `separator` tinted a touch fainter than the parts:
    /// the parts inherit the bar's `.secondary` tint, the separator renders in
    /// tertiary label. Used for both the breadcrumb (`›`) and the counts (`·`).
    private func joined(_ parts: [String], separator: String) -> AttributedString {
        var sep = AttributedString(separator)
        sep.foregroundColor = Color(nsColor: .tertiaryLabelColor)

        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(sep) }
            result.append(AttributedString(part))
        }
        return result
    }
}
