import AppKit
import SwiftUI

/// Renders a Page's frontmatter icon, tolerating BOTH SF Symbol names and
/// arbitrary glyph strings (emoji / custom text). `Image(systemName:)` draws a
/// broken placeholder for a non-symbol value, so a string that isn't a valid SF
/// Symbol falls back to a plain `Text` glyph; a nil/empty icon uses `doc.text`.
///
/// Single source for page-icon rendering across the renderers — table title
/// cells, gallery card headers, and the gallery drag preview all resolve the
/// same way, so a non-SF-Symbol icon renders identically everywhere.
struct PageIconGlyph: View {
    let icon: String?

    var body: some View {
        switch resolved {
        case .symbol(let name): Image(systemName: name)
        case .glyph(let text): Text(text)
        }
    }

    private enum Resolved {
        case symbol(String)
        case glyph(String)
    }

    private var resolved: Resolved {
        guard let icon, !icon.isEmpty else { return .symbol("doc.text") }
        if NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil {
            return .symbol(icon)
        }
        return .glyph(icon)
    }
}
