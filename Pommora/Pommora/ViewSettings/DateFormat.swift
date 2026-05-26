import Foundation

/// Per-property display format for Date / Date & Time property types.
///
/// Surfaced via `PropertyDefinition.dateFormat` (optional). nil = the
/// `.monthDayYearLong` default. Only Date and Date & Time property types
/// read this field; other types ignore it entirely.
///
/// Cases (illustrative renderings for 2026-03-04):
///   - `.monthDayLong` — "March 4"
///   - `.monthDayYearLong` — "March 4, 2026"
///   - `.numericShort` — "03-04"
///   - `.numericMedium` — "03-04-26"
///   - `.numericLong` — "03-04-2026"
///   - `.iso` — "2026-03-04" (matches on-disk storage)
///
/// Custom strftime-token format strings are deferred — tracked in Prospects.md
/// as "post-v1 Date Display as custom format".
enum DateFormat: String, Codable, Equatable, Sendable {
    case monthDayLong
    case monthDayYearLong
    case numericShort
    case numericMedium
    case numericLong
    case iso
}
