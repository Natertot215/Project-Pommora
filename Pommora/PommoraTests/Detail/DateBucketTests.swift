import Foundation
import Testing
@testable import Pommora

@Suite("DateBucketTests") struct DateBucketTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }
    @Test("month/day/year keys are zero-padded ISO and sort chronologically")
    func calendarKeys() {
        #expect(DateBucket.key(for: date(2026, 6, 15), granularity: .year) == "2026")
        #expect(DateBucket.key(for: date(2026, 6, 15), granularity: .month) == "2026-06")
        #expect(DateBucket.key(for: date(2026, 6, 15), granularity: .day) == "2026-06-15")
        #expect(DateBucket.key(for: date(2026, 1, 5), granularity: .month)
                < DateBucket.key(for: date(2026, 12, 5), granularity: .month))
    }
    @Test("ISO-8601 week pairs weekOfYear with yearForWeekOfYear")
    func isoWeek() {
        let k = DateBucket.key(for: date(2026, 12, 31), granularity: .week)
        #expect(k.hasPrefix("2026-W"))
        #expect(k.count == "2026-W53".count)
    }
    @Test("title renders non-empty containing the year for a month key")
    func monthTitle() {
        #expect(DateBucket.title(for: "2026-06", granularity: .month).contains("2026"))
    }
}
