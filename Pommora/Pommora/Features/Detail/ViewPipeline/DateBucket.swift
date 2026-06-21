import Foundation

/// Pure date → stable bucket key + human title. Keys are zero-padded ISO so
/// lexicographic order == chronological. Buckets are display-local (device
/// calendar + timezone), not UTC.
enum DateBucket {
    static func key(for date: Date, granularity: DateGranularity) -> String {
        switch granularity {
        case .year:
            return String(format: "%04d", Calendar.current.component(.year, from: date))
        case .month:
            let c = Calendar.current.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year!, c.month!)
        case .day:
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case .week:
            let iso = Calendar(identifier: .iso8601)
            let c = iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
            return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        }
    }

    static func title(for key: String, granularity: DateGranularity) -> String {
        switch granularity {
        case .year: return key
        case .week:
            let p = key.split(separator: "-")
            guard p.count == 2, p[1].first == "W" else { return key }
            return "Week \(p[1].dropFirst()), \(p[0])"
        case .month:
            let p = key.split(separator: "-")
            guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]),
                  let d = Calendar.current.date(from: DateComponents(year: y, month: m)) else { return key }
            return d.formatted(.dateTime.month(.wide).year())
        case .day:
            let p = key.split(separator: "-")
            guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let dd = Int(p[2]),
                  let d = Calendar.current.date(from: DateComponents(year: y, month: m, day: dd)) else { return key }
            return d.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
