import Foundation
import Testing
@testable import Pommora

@Suite("Recurrence")
struct RecurrenceTests {

    @Test("simple weekly recurrence round-trips")
    func weeklyRoundTrip() throws {
        let r = Recurrence(
            frequency: .weekly,
            interval: 1,
            firstDayOfWeek: 2,
            end: .occurrenceCount(10),
            daysOfWeek: [
                Recurrence.DayOfWeek(day: .monday, weekNumber: nil),
                Recurrence.DayOfWeek(day: .friday, weekNumber: -1)
            ],
            daysOfMonth: [],
            daysOfYear: [],
            weeksOfYear: [],
            monthsOfYear: [],
            setPositions: []
        )
        let data = try AtomicJSON.encode(r)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        #expect(decoded == r)
    }

    @Test("end can be omitted (nil)")
    func endNil() throws {
        let r = Recurrence(
            frequency: .daily, interval: 1, firstDayOfWeek: 1, end: nil,
            daysOfWeek: [], daysOfMonth: [], daysOfYear: [],
            weeksOfYear: [], monthsOfYear: [], setPositions: []
        )
        let data = try AtomicJSON.encode(r)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        #expect(decoded.end == nil)
    }

    @Test("end with date is correctly tagged")
    func endDate() throws {
        let until = Date(timeIntervalSince1970: 1716480000)
        let r = Recurrence(
            frequency: .monthly, interval: 2, firstDayOfWeek: 1, end: .endDate(until),
            daysOfWeek: [], daysOfMonth: [1, 15], daysOfYear: [],
            weeksOfYear: [], monthsOfYear: [], setPositions: []
        )
        let data = try AtomicJSON.encode(r)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Recurrence.self, from: data)
        if case let .endDate(d) = decoded.end {
            #expect(abs(d.timeIntervalSince1970 - until.timeIntervalSince1970) < 1)
        } else {
            Issue.record("expected .endDate case")
        }
    }

    @Test("snake_case keys on disk")
    func snakeCase() throws {
        let r = Recurrence(
            frequency: .yearly, interval: 1, firstDayOfWeek: 1, end: nil,
            daysOfWeek: [], daysOfMonth: [], daysOfYear: [],
            weeksOfYear: [], monthsOfYear: [], setPositions: [-1]
        )
        let data = try AtomicJSON.encode(r)
        let raw = String(data: data, encoding: .utf8)!
        #expect(raw.contains("\"first_day_of_week\""))
        #expect(raw.contains("\"days_of_week\""))
        #expect(raw.contains("\"days_of_month\""))
        #expect(raw.contains("\"set_positions\""))
    }
}
