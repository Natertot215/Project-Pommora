import Foundation

/// Per-property time-display setting for the Date property type, governing
/// whether (and how) the time portion renders alongside the date.
///
/// Surfaced via `PropertyDefinition.timeFormat` (optional). nil = `.none`
/// (date only) — so a Date property is date-only until time is turned on,
/// preserving the retired date-only type's behavior. Shown in the "Display
/// Time" picker.
///
///   - `.none`           — no time (date only)
///   - `.twelveHour`     — "3:45 PM"
///   - `.twentyFourHour` — "15:45"
enum TimeFormat: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case none
    case twelveHour
    case twentyFourHour

    var displayLabel: String {
        switch self {
        case .none: return "None"
        case .twelveHour: return "12 Hour"
        case .twentyFourHour: return "24 Hour"
        }
    }

    /// Whether the time component is shown at all. Drives the date-value vs
    /// date-time-value encoding and the editor's `displayedComponents`.
    var showsTime: Bool {
        self != .none
    }

    /// Renders the time portion, or nil for `.none`. Single source of truth for
    /// the time → string mapping (fixed patterns, not locale-dependent, so the
    /// 12h/24h choice is honoured regardless of region).
    func string(from date: Date) -> String? {
        let f = DateFormatter()
        f.timeZone = .current
        switch self {
        case .none:
            return nil
        case .twelveHour:
            f.dateFormat = "h:mm a"
            return f.string(from: date)
        case .twentyFourHour:
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
    }
}
