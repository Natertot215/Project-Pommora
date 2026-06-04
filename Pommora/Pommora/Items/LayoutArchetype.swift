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

/// How a promoted property renders on the main panel (LD-4). Tolerant decode so
/// new options add without breaking older files. The archetype sets a default;
/// a non-nil `PromotedProperty.display` overrides it.
enum PropertyDisplay: Codable, Hashable, Sendable {
    case inline, thumbnail, banner, chips, list
    case unknown(String)

    var rawValue: String {
        switch self {
        case .inline: return "inline"
        case .thumbnail: return "thumbnail"
        case .banner: return "banner"
        case .chips: return "chips"
        case .list: return "list"
        case .unknown(let s): return s
        }
    }
    init(rawValue: String) {
        switch rawValue {
        case "inline": self = .inline
        case "thumbnail": self = .thumbnail
        case "banner": self = .banner
        case "chips": self = .chips
        case "list": self = .list
        default: self = .unknown(rawValue)
        }
    }
    init(from decoder: any Decoder) throws {
        self = PropertyDisplay(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

/// A property promoted to a template's main panel, with an optional per-property
/// display override (LD-4). `display == nil` ⇒ the archetype's default treatment.
struct PromotedProperty: Codable, Hashable, Sendable {
    var id: String
    var display: PropertyDisplay?
    enum CodingKeys: String, CodingKey { case id, display }
}

/// Page open-in default (reserved/inert until PreviewWindow — LD-11).
enum OpenInMode: String, Codable, Hashable, Sendable {
    case preview
    case fullPage = "full_page"
}
