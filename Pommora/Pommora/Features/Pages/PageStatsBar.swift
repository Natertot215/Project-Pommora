import SwiftUI

/// The expandable Page stats row: breadcrumb on the left (Finder-style `›`
/// separators, each ancestor segment tappable for back-navigation), document
/// statistics on the right. The toggle chevron lives as an editor overlay in
/// `PageEditorView` (outside this bar) so the bar's height stays minimal.
struct PageStatsBar: View {
    /// Breadcrumb segments outermost-first. Ancestor crumbs carry an `action`
    /// for back-navigation; the current page segment has `action: nil`.
    let crumbs: [FooterCrumb]
    let stats: PageTextStats

    var body: some View {
        DetailFooterBar(crumbs: crumbs) {
            Text(joined(countComponents, separator: " · "))
                .foregroundStyle(.secondary)
                .help("Lines · Words · Characters")
        }
    }

    private var countComponents: [String] {
        [stats.lines, stats.words, stats.characters].map { $0.formatted() }
    }

    /// Joins `parts` with a `separator` tinted a touch fainter, matching the
    /// breadcrumb's own `›` separator treatment.
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
