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

    /// Encode a single-date selection back into a property value, choosing
    /// `.datetime` vs `.date` by whether the format shows time. A non-single
    /// or `nil` selection clears the value (`.null`).
    static func from(dateSelection selection: DateSelection?, timeFormat: TimeFormat) -> PropertyValue {
        guard case .single(let d)? = selection else { return .null }
        return timeFormat.showsTime ? .datetime(d) : .date(d)
    }
}
