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
