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

/// How `PropertyCellDisplay` should render a value once a `PropertyDisplay` mode
/// and the property's `PropertyType` are both known. The pure resolution surface
/// (`PropertyDisplay.treatment(for:)`) keeps the read-side branching unit-testable
/// without a SwiftUI snapshot — only `.default` ever changes the chip rendering.
enum DisplayTreatment: Hashable, Sendable {
    /// Image treatment for file properties (`thumbnail`/`banner` on `.file`).
    case image
    /// Vertical stack for relations (`list` on `.relation`).
    case verticalList
    /// Today's inline chip rendering — every other (display, type) pair.
    case `default`
}

extension PropertyDisplay {
    /// Resolves which read-side treatment a (display, type) pair yields.
    /// Only `.file` + `thumbnail`/`banner` and `.relation` + `list` diverge from
    /// the default inline chips; everything else (including `.inline`, `.chips`,
    /// and any `.unknown`) falls through to `.default`.
    func treatment(for type: PropertyType) -> DisplayTreatment {
        switch self {
        case .thumbnail, .banner:
            return type == .file ? .image : .default
        case .list:
            return type == .relation ? .verticalList : .default
        case .inline, .chips, .unknown:
            return .default
        }
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
