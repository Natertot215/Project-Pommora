import SwiftUI

/// Rendering primitive for File property values.
///
/// Quaternary fill + chain-link SF Symbol + filename truncated at 13 chars
/// with `…` (per the locked spec). Distinct visual class from PropertyChip
/// (vivid colors, full-name) and RelationChip (default-grey, rounded
/// rectangle) — files get their own attachment-language affordance.
///
/// Multi-file File values render multiple FileChips side-by-side at the
/// call-site level; the chip itself is single-file.
struct FileChip: View {
    let filename: String

    private let maxDisplayChars: Int = 13
    private let cornerRadius: CGFloat = 4

    private var truncated: String {
        guard filename.count > maxDisplayChars else { return filename }
        return String(filename.prefix(maxDisplayChars)) + "…"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
            Text(truncated)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .help(filename)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.quaternarySystemFill))
        )
    }
}
