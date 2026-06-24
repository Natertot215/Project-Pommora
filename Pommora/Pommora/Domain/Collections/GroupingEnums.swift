/// How a property's groups are ordered. One enum backs all groupable types;
/// the pane exposes a type-specific label subset.
enum GroupOrderMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case configured  // schema option order (Select "Default" / Status & Date "Ascending" / Checkbox "Off")
    case reversed    // configured flipped ("Descending" / Checkbox "On")
    case manual      // the PropertyGrouping.order array
}

enum DateGranularity: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case day, week, month, year
}

enum EmptyPlacement: String, Codable, Equatable, Hashable, Sendable {
    case top, bottom
}
