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

    /// Picker constraint for a Relation property. Five mutually-exclusive scope kinds;
    /// no fallback "anywhere" scope (per Properties.md § "Relation scope").
    ///
    /// On-disk shape is a tagged object: `{"kind": "<discriminator>", "<id-field>": "..."}`.
    /// Container scopes (page_type / item_type / page_collection / item_collection) carry
    /// a target ULID; context_tier carries the tier number (1/2/3).
    ///
    /// Container scopes are mandatorily paired with a `dual_property` reverse on the target
    /// Type's sidecar; context_tier rejects dual (the reverse view is SQLite-query-derived).
    enum RelationScope: Codable, Equatable, Hashable, Sendable {
        case pageType(String)
        case itemType(String)
        case pageCollection(String)
        case itemCollection(String)
        case contextTier(Int)

        private enum CodingKeys: String, CodingKey {
            case kind
            case pageTypeID = "page_type_id"
            case itemTypeID = "item_type_id"
            case pageCollectionID = "page_collection_id"
            case itemCollectionID = "item_collection_id"
            case tier
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "page_type":
                self = .pageType(try c.decode(String.self, forKey: .pageTypeID))
            case "item_type":
                self = .itemType(try c.decode(String.self, forKey: .itemTypeID))
            case "page_collection":
                self = .pageCollection(try c.decode(String.self, forKey: .pageCollectionID))
            case "item_collection":
                self = .itemCollection(try c.decode(String.self, forKey: .itemCollectionID))
            case "context_tier":
                self = .contextTier(try c.decode(Int.self, forKey: .tier))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "Unknown RelationScope.kind: \(kind)"
                )
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .pageType(let id):
                try c.encode("page_type", forKey: .kind)
                try c.encode(id, forKey: .pageTypeID)
            case .itemType(let id):
                try c.encode("item_type", forKey: .kind)
                try c.encode(id, forKey: .itemTypeID)
            case .pageCollection(let id):
                try c.encode("page_collection", forKey: .kind)
                try c.encode(id, forKey: .pageCollectionID)
            case .itemCollection(let id):
                try c.encode("item_collection", forKey: .kind)
                try c.encode(id, forKey: .itemCollectionID)
            case .contextTier(let tier):
                try c.encode("context_tier", forKey: .kind)
                try c.encode(tier, forKey: .tier)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case numberFormat = "number_format"
        case dateIncludesTime = "date_includes_time"
        case selectOptions = "select_options"
        case relationScope = "relation_scope"
    }
}
