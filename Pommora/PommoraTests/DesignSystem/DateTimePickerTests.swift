import Foundation
import Testing
@testable import Pommora

/// Coverage for the custom DateTimePicker's pure logic: the calendar-month
/// grid math (`CalendarMonth`), selection day-role classification
/// (`DateSelection`), and the date/time arithmetic (`DateTimeMath`). All
/// SwiftUI-free, so the grid bug class (clipped 6-week months, locale first
/// weekday) and the 12/24-hour conversions are proven without a view.
@Suite("DateTimePicker") struct DateTimePickerTests {
    /// Fixed Sunday-first Gregorian calendar in UTC, for deterministic grids
    /// regardless of the test host's locale/timezone.
    private static func sundayFirst() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1  // Sunday
        return c
    }

    private static func day(_ y: Int, _ m: Int, _ d: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - CalendarMonth grid math

    @Test func gridIsAlwaysWholeWeeks() {
        let cal = Self.sundayFirst()
        for month in 1...12 {
            let m = CalendarMonth(containing: Self.day(2025, month, 15, cal), calendar: cal)
            #expect(m.days.count % 7 == 0)
            #expect(m.days.count >= 28 && m.days.count <= 42)
        }
    }

    @Test func sixWeekMonthIsNotClipped() {
        // March 2025 starts Saturday (Sunday-first) → 6 rows (42 days). The
        // reference's hardcoded 5×7 would have dropped the last days.
        let cal = Self.sundayFirst()
        let march = CalendarMonth(containing: Self.day(2025, 3, 10, cal), calendar: cal)
        #expect(march.days.count == 42)
        // Grid starts on the Sunday before March 1 = Feb 23 2025.
        #expect(cal.isDate(march.days.first!, inSameDayAs: Self.day(2025, 2, 23, cal)))
        // The 1st sits at the leading offset (index 6 here).
        #expect(cal.isDate(march.days[6], inSameDayAs: Self.day(2025, 3, 1, cal)))
        // March 31 is present (not clipped).
        #expect(march.days.contains { cal.isDate($0, inSameDayAs: Self.day(2025, 3, 31, cal)) })
    }

    @Test func fourWeekMonthIsExact() {
        // Feb 2026 starts Sunday (Sunday-first), 28 days → exactly 4 rows.
        let cal = Self.sundayFirst()
        let feb = CalendarMonth(containing: Self.day(2026, 2, 14, cal), calendar: cal)
        #expect(feb.days.count == 28)
        #expect(cal.isDate(feb.days.first!, inSameDayAs: Self.day(2026, 2, 1, cal)))
        #expect(cal.isDate(feb.days.last!, inSameDayAs: Self.day(2026, 2, 28, cal)))
    }

    @Test func firstWeekdayRespected() {
        var cal = Self.sundayFirst()
        cal.firstWeekday = 2  // Monday
        let m = CalendarMonth(containing: Self.day(2026, 3, 10, cal), calendar: cal)
        #expect(m.weekdaySymbols.count == 7)
        #expect(m.weekdaySymbols.first == cal.shortWeekdaySymbols[1])  // Monday
    }

    @Test func addingMonthsCrossesYear() {
        let cal = Self.sundayFirst()
        let dec = CalendarMonth(containing: Self.day(2026, 12, 5, cal), calendar: cal)
        let jan = dec.adding(months: 1)
        #expect(cal.component(.year, from: jan.monthStart) == 2027)
        #expect(cal.component(.month, from: jan.monthStart) == 1)
    }

    @Test func isInMonthDiscriminatesLeadingTrailing() {
        let cal = Self.sundayFirst()
        let march = CalendarMonth(containing: Self.day(2025, 3, 10, cal), calendar: cal)
        #expect(march.isInMonth(Self.day(2025, 3, 1, cal)))
        #expect(!march.isInMonth(Self.day(2025, 2, 23, cal)))  // leading
    }

    // MARK: - DateSelection day roles

    @Test func singleRole() {
        let cal = Self.sundayFirst()
        let sel = DateSelection.single(Self.day(2026, 6, 10, cal))
        #expect(sel.role(of: Self.day(2026, 6, 10, cal), calendar: cal) == .selected)
        #expect(sel.role(of: Self.day(2026, 6, 11, cal), calendar: cal) == .none)
    }

    @Test func rangeRoles() {
        let cal = Self.sundayFirst()
        let sel = DateSelection.range(Self.day(2026, 6, 10, cal), Self.day(2026, 6, 14, cal))
        #expect(sel.role(of: Self.day(2026, 6, 10, cal), calendar: cal) == .rangeStart)
        #expect(sel.role(of: Self.day(2026, 6, 14, cal), calendar: cal) == .rangeEnd)
        #expect(sel.role(of: Self.day(2026, 6, 12, cal), calendar: cal) == .between)
        #expect(sel.role(of: Self.day(2026, 6, 9, cal), calendar: cal) == .none)
        #expect(sel.role(of: Self.day(2026, 6, 15, cal), calendar: cal) == .none)
    }

    @Test func rangeRoleIgnoresTimeOfDay() {
        // Endpoints carrying a time-of-day must not shift the day boundary.
        let cal = Self.sundayFirst()
        let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 23, minute: 30))!
        let end = cal.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1, minute: 0))!
        let sel = DateSelection.range(start, end)
        #expect(sel.role(of: Self.day(2026, 6, 11, cal), calendar: cal) == .between)
        #expect(sel.role(of: Self.day(2026, 6, 9, cal), calendar: cal) == .none)
        #expect(sel.role(of: Self.day(2026, 6, 13, cal), calendar: cal) == .none)
    }

    @Test func anchorDate() {
        let cal = Self.sundayFirst()
        let d = Self.day(2026, 6, 10, cal)
        #expect(DateSelection.single(d).anchorDate == d)
        #expect(DateSelection.range(d, Self.day(2026, 6, 20, cal)).anchorDate == d)
    }

    // MARK: - DateTimeMath

    @Test func hour24FromHour12() {
        #expect(DateTimeMath.hour24(fromHour12: 12, isPM: false) == 0)   // 12 AM = midnight
        #expect(DateTimeMath.hour24(fromHour12: 12, isPM: true) == 12)   // 12 PM = noon
        #expect(DateTimeMath.hour24(fromHour12: 1, isPM: false) == 1)
        #expect(DateTimeMath.hour24(fromHour12: 1, isPM: true) == 13)
        #expect(DateTimeMath.hour24(fromHour12: 11, isPM: true) == 23)
    }

    @Test func hour12FromHour24() {
        #expect(DateTimeMath.hour12(fromHour24: 0).hour == 12)
        #expect(DateTimeMath.hour12(fromHour24: 0).isPM == false)
        #expect(DateTimeMath.hour12(fromHour24: 12).hour == 12)
        #expect(DateTimeMath.hour12(fromHour24: 12).isPM == true)
        #expect(DateTimeMath.hour12(fromHour24: 13).hour == 1)
        #expect(DateTimeMath.hour12(fromHour24: 13).isPM == true)
        #expect(DateTimeMath.hour12(fromHour24: 23).hour == 11)
    }

    @Test func combinePreservesDayAndTime() {
        let cal = Self.sundayFirst()
        let theDay = Self.day(2026, 3, 1, cal)
        let theTime = cal.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 15, minute: 45))!
        let combined = DateTimeMath.combine(day: theDay, time: theTime, calendar: cal)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: combined)
        #expect(c.year == 2026 && c.month == 3 && c.day == 1)
        #expect(c.hour == 15 && c.minute == 45)
    }

    @Test func settingHourMinuteKeepsDay() {
        let cal = Self.sundayFirst()
        let base = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9, minute: 0))!
        let updated = DateTimeMath.setting(hour: 17, minute: 30, on: base, calendar: cal)
        let c = cal.dateComponents([.day, .hour, .minute], from: updated)
        #expect(c.day == 1 && c.hour == 17 && c.minute == 30)
    }
}
