import SwiftUI

/// Rendering primitive for URL ("Link") property values.
///
/// Pure accent-blue text — no chip chrome, no fill. Strips the `https://`
/// or `http://` scheme prefix from the displayed string (the stored
/// PropertyValue retains the full URL). Truncates at 15 chars with `…`.
/// Click reveals the full URL for editing (popover wired by
/// PropertyCellEditor at Phase H).
///
/// Lives under Properties/Chips/ for naming consistency with PropertyChip /
/// RelationChip / FileChip even though it renders as styled text rather
/// than a capsule/rectangle. Treat it as the "URL display primitive."
struct LinkChip: View {
    let url: URL

    private let maxDisplayChars: Int = 15

    private var display: String {
        let raw = url.absoluteString
        // Strip scheme prefix; otherwise truncate the absolute string.
        let stripped: String
        if raw.hasPrefix("https://") {
            stripped = String(raw.dropFirst("https://".count))
        } else if raw.hasPrefix("http://") {
            stripped = String(raw.dropFirst("http://".count))
        } else {
            stripped = raw
        }
        guard stripped.count > maxDisplayChars else { return stripped }
        return String(stripped.prefix(maxDisplayChars)) + "…"
    }

    var body: some View {
        Text(display)
            .font(.system(size: 12))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .help(url.absoluteString)
    }
}
