import Foundation

/// Per-vault default for how Pages open (`open_in` on the PageType sidecar).
/// Tight raw-value enum (enum+switch HARD RULE): two shipping modes, no
/// tolerant arm — an unrecognized on-disk value fails decode loudly.
enum OpenInMode: String, Codable, Sendable, CaseIterable {
    /// Opens the page in the PagePreview window (ships P5).
    case compact
    /// Opens the page in the main detail pane.
    case window
}

/// How a property value renders in page surfaces (columns/cells). Tolerant
/// decode so new options add without breaking older files.
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
