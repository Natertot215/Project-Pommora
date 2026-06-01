import SwiftUI

/// The expanded Page stats row: a Finder-style breadcrumb (`Vault > Collection
/// > Page`, clickable to navigate) on the left, `Lines · Words · Characters` on
/// the right. The toggle chevron lives as an editor overlay in `PageEditorView`
/// (outside this bar) so the bar's height stays minimal.
struct PageStatsBar: View {
    let vault: PageType
    let collection: PageCollection?
    let page: PageMeta
    let stats: PageTextStats
    let onNavigate: (SidebarSelection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            PathBreadcrumb(crumbs: entries.map(\.crumb)) { index in
                onNavigate(entries[index].navigation)
            }
            .fixedSize()

            Spacer(minLength: 12)

            Text(countsAttributed)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .help("Lines · Words · Characters")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    /// Breadcrumb crumbs paired with where each navigates: Vault > [Collection]
    /// > Page. The Page crumb navigates to itself (effectively a no-op).
    private var entries: [(crumb: PathBreadcrumb.Crumb, navigation: SidebarSelection)] {
        var result: [(PathBreadcrumb.Crumb, SidebarSelection)] = [
            (PathBreadcrumb.Crumb(title: vault.title), .pageType(vault))
        ]
        if let collection {
            result.append((PathBreadcrumb.Crumb(title: collection.title), .collection(collection)))
        }
        result.append((PathBreadcrumb.Crumb(title: page.title), .page(page)))
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
