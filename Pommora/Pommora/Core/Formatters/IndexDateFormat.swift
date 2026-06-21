import Foundation

/// Single source for the index's ISO-8601 timestamp encoding. Read (filter) and
/// write (upsert/rebuild) paths MUST share this, or a datetime filter string fails
/// to match a stored fractional-second timestamp.
enum IndexDateFormat {
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
