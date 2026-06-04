import Foundation

/// The single source of truth for mapping a property value to/from the
/// `DateTimePicker`'s `DateSelection`. Both the table-cell editor and the
/// inspector-row editor route through this, rather than each re-implementing
/// the `.date`/`.datetime` ⇄ `.single` adapter (DRY).
extension PropertyValue {
    /// The single-date selection this value represents (a `.date` or
    /// `.datetime` → `.single`), or `nil` for any other / unset value.
    var dateSelection: DateSelection? {
        switch self {
        case .date(let d), .datetime(let d): return .single(d)
        default: return nil
        }
    }

    /// Encode a single-date selection back into a property value. Stores
    /// `.datetime` only when both the format shows time AND `isTimeSet` is
    /// true — a date with no explicit time becomes `.date` even on a datetime
    /// property, so the display can skip the time portion. A non-single or
    /// `nil` selection clears the value (`.null`).
    static func from(
        dateSelection selection: DateSelection?,
        timeFormat: TimeFormat,
        isTimeSet: Bool = true
    ) -> PropertyValue {
        guard case .single(let d)? = selection else { return .null }
        return (timeFormat.showsTime && isTimeSet) ? .datetime(d) : .date(d)
    }
}
