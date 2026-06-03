import Foundation

/// Pure (no-SwiftUI) model of one calendar month's grid. Given any date and a
/// `Calendar`, it produces the days to render — leading days borrowed from the
/// previous month, this month's own days, and trailing days from the next —
/// padded to a whole number of weeks.
///
/// The week count is **computed from the month (5 or 6), never hardcoded** —
/// a 31-day month starting late in the week needs six rows, and a clipped grid
/// would simply drop the last days. Everything is locale-aware via the
/// calendar's `firstWeekday`, so a Monday-first region reads Mon…Sun.
///
/// Kept free of SwiftUI so the grid math is unit-testable in isolation.
struct CalendarMonth: Equatable, Sendable {
    let calendar: Calendar
    /// The first instant of the represented month (normalized internally).
    let monthStart: Date

    init(containing date: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let comps = calendar.dateComponents([.year, .month], from: date)
        self.monthStart = calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    /// Weekday header symbols ordered by the calendar's `firstWeekday`.
    var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols       // [Sun, Mon, … Sat]
        let shift = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// The grid days — always a multiple of 7, sized to the month (5 or 6 rows).
    var days: [Date] {
        guard
            let range = calendar.range(of: .day, in: .month, for: monthStart),
            let firstWeekday = calendar.dateComponents([.weekday], from: monthStart).weekday
        else { return [] }

        let daysInMonth = range.count
        // Leading offset: how far the 1st sits past the calendar's first weekday.
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let weeks = Int((Double(leading + daysInMonth) / 7.0).rounded(.up))
        let cellCount = weeks * 7

        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart)
        else { return [] }

        return (0..<cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    /// Localized month name ("December"), via `calendar.monthSymbols` rather
    /// than a per-call `DateFormatter` (one of Foundation's costliest allocs,
    /// and this is read repeatedly during menu layout).
    var monthName: String {
        let monthIndex = calendar.component(.month, from: monthStart) - 1
        return calendar.monthSymbols.indices.contains(monthIndex)
            ? calendar.monthSymbols[monthIndex]
            : ""
    }

    /// The 4-digit year.
    var year: Int { calendar.component(.year, from: monthStart) }

    /// "December 2026".
    var title: String { "\(monthName) \(year)" }

    func isInMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
    }

    /// A new month offset by `months` from this one (negative = earlier).
    func adding(months: Int) -> CalendarMonth {
        let shifted = calendar.date(byAdding: .month, value: months, to: monthStart) ?? monthStart
        return CalendarMonth(containing: shifted, calendar: calendar)
    }
}
