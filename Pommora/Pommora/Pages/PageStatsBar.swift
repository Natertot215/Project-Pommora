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
            Text(breadcrumbAttributed)
            Spacer(minLength: 12)
            Text(countsAttributed)
                .help("Lines · Words · Characters")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    /// "Vault › Collection › Page" — component names inherit the `.secondary`
    /// tint; the `›` separators are a touch fainter (tertiary), Finder-style.
    private var breadcrumbAttributed: AttributedString {
        var separator = AttributedString(" › ")
        separator.foregroundColor = Color(nsColor: .tertiaryLabelColor)

        var result = AttributedString()
        for (index, title) in breadcrumb.enumerated() {
            if index > 0 { result.append(separator) }
            result.append(AttributedString(title))
        }
        return result
    }

    /// "12 · 340 · 1,890" — numbers inherit the `.secondary` tint; the `·`
    /// separators are a touch fainter (tertiary label).
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
