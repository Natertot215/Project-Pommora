import Foundation

/// Per-property display format for the Date property type (date portion only;
/// time is governed separately by `TimeFormat`).
///
/// Surfaced via `PropertyDefinition.dateFormat` (optional). nil = the `.full`
/// default. The picker offers exactly these four, labelled by format-type name
/// (`displayLabel`) — there is no "Default" row.
///
///   - `.short`        — "March 1st"                  (month + ordinal day, no year)
///   - `.full`         — "Wednesday, March 1st 2026"  (weekday + month + ordinal day + year)
///   - `.dayMonthYear` — "01/03/2026"                 (DD/MM/YYYY)
///   - `.monthDayYear` — "03/01/2026"                 (MM/DD/YYYY)
///
/// Legacy values (`monthDayYearLong`, `numericShort`, …, `iso`, and the interim
/// `long`) migrate on decode (see `init(from:)`) so older sidecars keep loading.
enum DateFormat: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case short
    case full
    case dayMonthYear
    case monthDayYear

    /// Format-type name shown in the "Display Date" picker — never an example
    /// date (per Nathan's 2026-06-02 direction).
    var displayLabel: String {
        switch self {
        case .short: return "Short Date"
        case .full: return "Full Date"
        case .dayMonthYear: return "DD/MM/YYYY"
        case .monthDayYear: return "MM/DD/YYYY"
        }
    }

    /// Renders the date portion (no time). Single source of truth for the
    /// date → string mapping. The ordinal day ("1st") is composed manually —
    /// `DateFormatter` can't emit an ordinal day component.
    func string(from date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = .current
        switch self {
        case .short:
            f.dateFormat = "MMMM"
            return "\(f.string(from: date)) \(Self.ordinalDay(from: date))"
        case .full:
            f.dateFormat = "EEEE"
            let weekday = f.string(from: date)
            f.dateFormat = "MMMM"
            let month = f.string(from: date)
            f.dateFormat = "yyyy"
            return "\(weekday), \(month) \(Self.ordinalDay(from: date)) \(f.string(from: date))"
        case .dayMonthYear:
            f.dateFormat = "dd/MM/yyyy"
            return f.string(from: date)
        case .monthDayYear:
            f.dateFormat = "MM/dd/yyyy"
            return f.string(from: date)
        }
    }

    /// English ordinal day, e.g. 1 → "1st", 22 → "22nd", 13 → "13th".
    private static func ordinalDay(from date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch day % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    /// Legacy → current migration. v0.3.1 originals + the interim 2026-06-02
    /// tokens (`long` / `medium` / `full`-as-locale) all fold into the four
    /// current cases. `.short` rawValue is reused (handled by
    /// `DateFormat(rawValue:)` directly); the year-bearing forms collapse to `.full`.
    private static let legacy: [String: DateFormat] = [
        "monthDayLong": .short,
        "monthDayYearLong": .full,
        "numericShort": .monthDayYear,
        "numericMedium": .monthDayYear,
        "numericLong": .monthDayYear,
        "iso": .full,
        "long": .full,
        "medium": .full,
    ]

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // New value → legacy value → default. Never throws: a display-only field
        // must not fail the whole PropertyDefinition load on an unknown token.
        self = DateFormat(rawValue: raw) ?? DateFormat.legacy[raw] ?? .full
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
