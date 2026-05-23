import Foundation

/// One property schema entry inside a PageType / ItemType / Tasks / Events
/// per-kind sidecar (`_pagetype.json` / `_itemtype.json` / `_taskconfig.json`
/// / `_eventconfig.json`). Type-specific config fields live as optionals on
/// this struct; only the ones relevant to `type` should be populated.
struct PropertyDefinition: Codable, Equatable, Identifiable, Hashable, Sendable {
    var name: String  // user-facing label; doubles as property key
    var type: PropertyType

    // Type-specific config (all optional, only filled when relevant):
    var numberFormat: NumberFormat?  // number
    var dateIncludesTime: Bool?  // date — irrelevant for `datetime` type
    var selectOptions: [SelectOption]?  // select + multiSelect
    var relationScope: RelationScope?  // relation

    var id: String { name }

    struct SelectOption: Codable, Equatable, Hashable, Identifiable, Sendable {
        var value: String  // canonical key (immutable post-create ideally)
        var label: String  // user-facing
        var color: SelectColor?

        var id: String { value }
    }

    enum SelectColor: String, Codable, CaseIterable, Hashable, Sendable {
        case gray, brown, orange, yellow, green, blue, purple, pink, red
    }

    enum NumberFormat: String, Codable, CaseIterable, Hashable, Sendable {
        case integer, decimal, percent, currency
    }

    enum RelationScope: String, Codable, CaseIterable, Hashable, Sendable {
        case sameVault = "same_vault"
        case anywhere
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case numberFormat = "number_format"
        case dateIncludesTime = "date_includes_time"
        case selectOptions = "select_options"
        case relationScope = "relation_scope"
    }
}
