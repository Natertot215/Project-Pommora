import Foundation

/// Type-erased property value used in Item / Page / Agenda `properties` dictionaries.
/// Custom Codable inspects the JSON shape per-value:
/// - JSON number → `.number(Double)`
/// - JSON bool   → `.checkbox(Bool)`
/// - JSON null   → `.null`
/// - JSON object `{"$rel": "..."}` → `.relation(String)` (ULID of target entity)
/// - JSON object `{"$status": "..."}` → `.status(String)` (option value)
/// - JSON array of strings → `.multiSelect([String])`
/// - JSON array of objects → `.file([FileRef])`
/// - JSON string → `.url`/`.date`/`.datetime`/`.select` (disambiguated by shape;
///                  ISO-8601 strings decode as `.datetime` if they include time, `.date` if not;
///                  URLs validate via `URL(string:)`; anything else is `.select`)
///
/// Relation encoding: `.relation(id)` writes `{"$rel": id}` so external agents and the
/// graph-view indexer can identify cross-entity edges from any single file without consulting
/// the Type schema. Satisfies Pommora load-bearing constraint #3.
///
/// Status encoding: `.status(value)` writes `{"$status": value}` for the same reason — it
/// disambiguates status (grouped picker) from `.select` (flat picker) at the value layer,
/// since both store a single option string. Properties.md describes the conceptual on-disk
/// shape (`"<option value>"`); the manager layer can translate between schema-aware string
/// form and tagged form, but the Codable layer needs the tag for round-trip stability.
///
/// Date vs datetime: `.date` writes a yyyy-MM-dd string (UTC); `.datetime` writes full
/// ISO-8601 with timezone. On decode: ISO-8601 with `T` → `.datetime`, else yyyy-MM-dd → `.date`.
///
/// `.lastEditedTime` is a **virtual** case — it is never stored on disk (the value derives from
/// the file's `modified_at` at read time). Encoding `.lastEditedTime` throws `EncodingError.invalidValue`
/// to prevent accidental persistence.
enum PropertyValue: Codable, Equatable, Hashable, Sendable {
    case number(Double)
    case checkbox(Bool)
    case date(Date)
    case datetime(Date)
    case select(String)
    case multiSelect([String])
    case status(String)  // option value; encodes as {"$status": value}
    case relation(String)  // ULID of target entity; encodes as {"$rel": id}
    case url(URL)
    case file([FileRef])
    case lastEditedTime  // virtual — never persisted; encoding throws
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
        // Array branch: prefer file (array of objects) over multi-select (array of strings)
        if let files = try? c.decode([FileRef].self), !files.isEmpty {
            self = .file(files)
            return
        }
        if let arr = try? c.decode([String].self) {
            self = .multiSelect(arr)
            return
        }
        // Empty array → treat as empty file list (multi-select empty arrays should not occur
        // at the storage layer; if needed, the manager can normalise).
        if let empties = try? c.decode([FileRef].self), empties.isEmpty {
            self = .file([])
            return
        }
        // Tagged-object: {"$rel": "01H..."} or {"$status": "value"}
        if let obj = try? c.decode([String: String].self), obj.count == 1 {
            if let id = obj["$rel"] {
                self = .relation(id)
                return
            }
            if let value = obj["$status"] {
                self = .status(value)
                return
            }
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
        case .status(let value): try c.encode(["$status": value])
        case .relation(let id): try c.encode(["$rel": id])
        case .url(let u): try c.encode(u.absoluteString)
        case .file(let refs): try c.encode(refs)
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
        case .lastEditedTime:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription:
                        "PropertyValue.lastEditedTime is virtual and must not be persisted; "
                        + "derive from the file's modified_at at read time."
                )
            )
        }
    }
}
