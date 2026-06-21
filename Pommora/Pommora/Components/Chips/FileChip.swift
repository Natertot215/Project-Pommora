import SwiftUI

/// Rendering primitive for a File property value — `.chipStyle(.fileTag)` chrome,
/// chain-link (or `photo`) glyph + filename truncated at 13 chars.
///
/// Multi-file values render several FileChips side-by-side at the call site;
/// the chip itself is single-file.
struct FileChip: View {
    let filename: String
    /// Leading glyph — defaults to the chain-link; image refs pass "photo".
    var icon: String = "link"

    private let maxDisplayChars: Int = 13

    private var truncated: String {
        guard filename.count > maxDisplayChars else { return filename }
        return String(filename.prefix(maxDisplayChars)) + "…"
    }

    var body: some View {
        HStack(spacing: PUI.Chip.fileIconTitleGap) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(PUI.Colors.labelSecondary)
            Text(truncated)
                .font(PUI.Typography.Fixed.f12)
                .foregroundStyle(PUI.Colors.labelPrimary)
                .lineLimit(1)
                .help(filename)
        }
        .chipStyle(.fileTag)
    }
}
