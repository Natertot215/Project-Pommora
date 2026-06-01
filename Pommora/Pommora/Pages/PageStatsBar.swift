import SwiftUI

/// The expanded Page stats row: `Vault / Collection` on the left, `Lines ·
/// Words · Characters` on the right. Display-only — the toggle chevron lives
/// as an editor overlay in `PageEditorView` (outside this bar) so the bar's
/// height stays minimal. The host owns visibility + `stats`.
struct PageStatsBar: View {
    let breadcrumb: String
    let stats: PageTextStats

    var body: some View {
        HStack(spacing: 0) {
            Text(breadcrumb)
            Spacer(minLength: 12)
            Text(countsAttributed)
                .help("Lines · Words · Characters")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
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
