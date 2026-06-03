import Foundation

/// Pure date/time arithmetic for the picker — extracted from the views so the
/// error-prone bits (recombining a day with a time, 12⇄24-hour conversion) are
/// unit-testable without SwiftUI, and shared rather than duplicated across the
/// calendar grid and the time row.
enum DateTimeMath {
    /// A date carrying `day`'s year/month/day but `time`'s hour/minute.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute], from: time)
        var c = DateComponents()
        c.year = d.year
        c.month = d.month
        c.day = d.day
        c.hour = t.hour
        c.minute = t.minute
        return calendar.date(from: c) ?? day
    }

    /// `date` with its hour/minute replaced, keeping the same calendar day.
    static func setting(hour: Int, minute: Int, on date: Date, calendar: Calendar = .current) -> Date {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        var c = DateComponents()
        c.year = d.year
        c.month = d.month
        c.day = d.day
        c.hour = hour
        c.minute = minute
        return calendar.date(from: c) ?? date
    }

    /// 12-hour clock value (1…12) + AM/PM → 24-hour (0…23).
    /// 12 AM → 0, 12 PM → 12.
    static func hour24(fromHour12 hour12: Int, isPM: Bool) -> Int {
        let h = hour12 % 12          // 12 → 0
        return isPM ? h + 12 : h
    }

    /// 24-hour (0…23) → 12-hour display value (1…12) + isPM.
    /// 0 → 12 AM, 12 → 12 PM.
    static func hour12(fromHour24 hour24: Int) -> (hour: Int, isPM: Bool) {
        let isPM = hour24 >= 12
        let h = hour24 % 12
        return (h == 0 ? 12 : h, isPM)
    }
}
