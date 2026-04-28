import SwiftUI

struct SidebarFileRow: View {
    let file: FileReference
    var hit: LibrarySearch.Hit? = nil

    var body: some View {
        if let hit {
            hitRow(hit)
        } else {
            HStack(spacing: 4) {
                Label(file.titleWithoutExtension, systemImage: iconName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(file.formatBadge)
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
            }
        }
    }

    private var iconName: String {
        file.isMarkdown ? "doc.richtext" : "doc.text"
    }

    @ViewBuilder
    private func hitRow(_ hit: LibrarySearch.Hit) -> some View {
        switch hit.kind {
        case .filename:
            HStack(spacing: 4) {
                Label {
                    Text(highlighted(file.titleWithoutExtension, matchedRange: hit.matchedRange))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: iconName)
                }
                Spacer(minLength: 0)
                Text(file.formatBadge)
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
            }

        case .heading(let text, let line):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlighted(text, matchedRange: hit.matchedRange))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(file.titleWithoutExtension)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Line \(line)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: iconName)
            }
        }
    }

    private func highlighted(_ source: String, matchedRange: Range<String.Index>) -> AttributedString {
        var attributed = AttributedString(source)
        let clamped = clampRange(matchedRange, in: source)
        if let lower = AttributedString.Index(clamped.lowerBound, within: attributed),
           let upper = AttributedString.Index(clamped.upperBound, within: attributed) {
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }

    private func clampRange(_ range: Range<String.Index>, in source: String) -> Range<String.Index> {
        let lower = min(max(range.lowerBound, source.startIndex), source.endIndex)
        let upper = min(max(range.upperBound, source.startIndex), source.endIndex)
        return lower..<upper
    }
}
