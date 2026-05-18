import Foundation

/// Type-erased property value used in Item / Page / Agenda `properties` dictionaries.
/// Custom Codable inspects the JSON shape per-value:
/// - JSON number → `.number(Double)`
/// - JSON bool   → `.checkbox(Bool)`
/// - JSON null   → `.null`
/// - JSON object `{"$rel": "..."}` → `.relation(String)` (ULID of target entity)
/// - JSON string → `.url`/`.date`/`.datetime`/`.select` (disambiguated by shape;
///                  ISO-8601 strings decode as `.datetime` if they include time, `.date` if not;
///                  URLs validate via `URL(string:)`; anything else is `.select`)
/// - JSON array  → `.multiSelect([String])`
///
/// Relation encoding: `.relation(id)` writes `{"$rel": id}` so external agents and the
/// graph-view indexer can identify cross-entity edges from any single file without consulting
/// the Vault schema. Satisfies Pommora load-bearing constraint #3.
///
/// Date vs datetime: `.date` writes a yyyy-MM-dd string (UTC); `.datetime` writes full
/// ISO-8601 with timezone. On decode: ISO-8601 with `T` → `.datetime`, else yyyy-MM-dd → `.date`.
enum PropertyValue: Codable, Equatable, Hashable, Sendable {
    case number(Double)
    case checkbox(Bool)
    case date(Date)
    case datetime(Date)
    case select(String)
    case multiSelect([String])
    case relation(String)  // ULID of target entity; encodes as {"$rel": id}
    case url(URL)
    case null

    // MARK: - Codable

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .checkbox(b)
            return
        }
        if let n = try? c.decode(Double.self) {
            self = .number(n)
            return
        }
        if let arr = try? c.decode([String].self) {
            self = .multiSelect(arr)
            return
        }
        // Tagged-object relation: {"$rel": "01H..."}
        if let obj = try? c.decode([String: String].self),
            obj.count == 1,
            let id = obj["$rel"]
        {
            self = .relation(id)
            return
        }
        if let s = try? c.decode(String.self) {
            // Try URL
            if let url = URL(string: s), url.scheme != nil {
                self = .url(url)
                return
            }
            // Try ISO-8601 datetime
            let isoDateTime = ISO8601DateFormatter()
            isoDateTime.formatOptions = [.withInternetDateTime]
            if let d = isoDateTime.date(from: s) {
                self = .datetime(d)
                return
            }
            // Try yyyy-MM-dd
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            if let d = dateFormatter.date(from: s) {
                self = .date(d)
                return
            }
            // Fallthrough: plain string → treat as select value
            self = .select(s)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "PropertyValue: unrecognised JSON shape"
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let n): try c.encode(n)
        case .checkbox(let b): try c.encode(b)
        case .select(let s): try c.encode(s)
        case .multiSelect(let xs): try c.encode(xs)
        case .relation(let id): try c.encode(["$rel": id])
        case .url(let u): try c.encode(u.absoluteString)
        case .null: try c.encodeNil()
        case .date(let d):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            try c.encode(f.string(from: d))
        case .datetime(let d):
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            try c.encode(iso.string(from: d))
        }
    }
}
