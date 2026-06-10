import Foundation

/// Item Window layout archetype. Typed + finite (enum+switch HARD RULE) but
/// forward-expandable: an unrecognized on-disk value decodes to `.unknown`
/// and round-trips unchanged (no data loss). `reserved` is a named 6th slot,
/// muted in the settings pane until promoted to a real archetype.
enum LayoutArchetype: Codable, Hashable, Sendable {
    case compact, standard, bannerTwoColumn, gallery, wide, reserved
    case unknown(String)

    var rawValue: String {
        switch self {
        case .compact: return "compact"
        case .standard: return "standard"
        case .bannerTwoColumn: return "banner_two_column"
        case .gallery: return "gallery"
        case .wide: return "wide"
        case .reserved: return "reserved"
        case .unknown(let s): return s
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "compact": self = .compact
        case "standard": self = .standard
        case "banner_two_column": self = .bannerTwoColumn
        case "gallery": self = .gallery
        case "wide": self = .wide
        case "reserved": self = .reserved
        default: self = .unknown(rawValue)
        }
    }

    init(from decoder: any Decoder) throws {
        self = LayoutArchetype(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// Settings-pane roster (the 5 shipping + reserved; never `.unknown`).
    static let selectable: [LayoutArchetype] = [.compact, .standard, .bannerTwoColumn, .gallery, .wide, .reserved]

    /// Overflow surface this archetype declares (LD-3): a side-pane inspector vs a
    /// dropdown. One boolean fact — no separate enum (promote to one only if a
    /// third overflow style ever appears).
    var usesInspector: Bool { self == .bannerTwoColumn }
}

/// Whether inspector/segment property rows show the property title (`standard`)
/// or render value-only (`compact`). Tolerant decode so a future mode adds
/// without breaking older files. V1 ships `.standard`; `.compact` is
/// present-but-disabled. Optional on `ItemTemplateConfig`: absent ⇒ nil and the
/// key is never written, so callers default at read time (`?? .standard`).
enum PropertyLayoutMode: Codable, Equatable, Hashable, Sendable {
    case standard, compact, unknown(String)
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "standard": self = .standard
        case "compact": self = .compact
        default: self = .unknown(raw)
        }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .standard: try c.encode("standard")
        case .compact: try c.encode("compact")
        case .unknown(let r): try c.encode(r)
        }
    }
}

/// A property promoted to a template's main panel, with an optional per-property
/// display override (LD-4). `display == nil` ⇒ the archetype's default treatment.
/// (`PropertyDisplay` itself is page-native — `Vaults/PageDisplay.swift`.)
struct PromotedProperty: Codable, Hashable, Sendable {
    var id: String
    var display: PropertyDisplay?
    enum CodingKeys: String, CodingKey { case id, display }
}
