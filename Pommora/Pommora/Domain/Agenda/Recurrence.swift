import Foundation

/// JSON shape matching `EKRecurrenceRule`. Per spec validation pass — `EKRecurrenceRule`
/// is immutable on the EventKit side, so on sync we always construct a fresh rule
/// from this struct rather than mutating in place.
struct Recurrence: Codable, Equatable, Hashable, Sendable {
    var frequency: Frequency
    var interval: Int  // every N units (≥ 1)
    var firstDayOfWeek: Int  // 1=Sun … 7=Sat; affects weekly semantics
    var end: End?
    var daysOfWeek: [DayOfWeek]
    var daysOfMonth: [Int]  // e.g. [1, 15] = "1st and 15th"
    var daysOfYear: [Int]
    var weeksOfYear: [Int]
    var monthsOfYear: [Int]
    var setPositions: [Int]  // e.g. [-1] = "last instance"

    enum Frequency: String, Codable, CaseIterable, Hashable, Sendable {
        case daily, weekly, monthly, yearly
    }

    enum End: Codable, Equatable, Hashable, Sendable {
        case occurrenceCount(Int)
        case endDate(Date)

        private enum CodingKeys: String, CodingKey { case kind, value }
        private enum Kind: String, Codable {
            case occurrenceCount = "occurrence_count"
            case endDate = "end_date"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .kind)
            switch kind {
            case .occurrenceCount: self = .occurrenceCount(try c.decode(Int.self, forKey: .value))
            case .endDate: self = .endDate(try c.decode(Date.self, forKey: .value))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .occurrenceCount(let n):
                try c.encode(Kind.occurrenceCount, forKey: .kind)
                try c.encode(n, forKey: .value)
            case .endDate(let d):
                try c.encode(Kind.endDate, forKey: .kind)
                try c.encode(d, forKey: .value)
            }
        }
    }

    struct DayOfWeek: Codable, Equatable, Hashable, Sendable {
        var day: Day
        var weekNumber: Int?  // -5…-1 or 1…5; "last Friday" = .friday, -1

        enum Day: String, Codable, CaseIterable, Hashable, Sendable {
            case sunday = "sun"
            case monday = "mon"
            case tuesday = "tue"
            case wednesday = "wed"
            case thursday = "thu"
            case friday = "fri"
            case saturday = "sat"
        }

        enum CodingKeys: String, CodingKey {
            case day
            case weekNumber = "week_number"
        }
    }

    enum CodingKeys: String, CodingKey {
        case frequency, interval, end
        case firstDayOfWeek = "first_day_of_week"
        case daysOfWeek = "days_of_week"
        case daysOfMonth = "days_of_month"
        case daysOfYear = "days_of_year"
        case weeksOfYear = "weeks_of_year"
        case monthsOfYear = "months_of_year"
        case setPositions = "set_positions"
    }
}
