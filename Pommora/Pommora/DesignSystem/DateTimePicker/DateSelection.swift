import Foundation

/// What the date picker has selected. `.single` is one date (what property
/// cells use); `.range` is a start/end span (reserved for Agenda events / the
/// Component-Library showcase). The picker binds `DateSelection?` — nil means
/// nothing selected.
enum DateSelection: Equatable, Hashable, Sendable {
    case single(Date)
    case range(Date, Date)

    /// Which selection behavior a picker instance is in.
    enum Mode: Sendable { case single, range }

    /// Where a given day sits relative to the selection — drives the cell fill.
    enum DayRole: Equatable, Sendable {
        case none
        case selected      // single-mode selected day
        case rangeStart
        case rangeEnd
        case between       // strictly inside a range (the low-opacity band)
    }

    /// The date a picker should open on (the start, for a range).
    var anchorDate: Date {
        switch self {
        case .single(let d): return d
        case .range(let start, _): return start
        }
    }

    /// Classify `day` against this selection. Comparison is by calendar day
    /// (start-of-day), so a stored time-of-day never shifts the boundary.
    func role(of day: Date, calendar: Calendar = .current) -> DayRole {
        switch self {
        case .single(let d):
            return calendar.isDate(day, inSameDayAs: d) ? .selected : .none
        case .range(let a, let b):
            let startDay = calendar.startOfDay(for: min(a, b))
            let endDay = calendar.startOfDay(for: max(a, b))
            let d = calendar.startOfDay(for: day)
            if d == startDay { return .rangeStart }
            if d == endDay { return .rangeEnd }
            return (d > startDay && d < endDay) ? .between : .none
        }
    }
}
