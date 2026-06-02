import Foundation
import Yams

/// Reads and writes Markdown files with a YAML-frontmatter envelope.
///
/// File format:
/// ```
/// ---
/// <YAML>
/// ---
///
/// <body>
/// ```
///
/// On read:
/// - If the file starts with `---\n`, parses the frontmatter up to the next `\n---\n`.
/// - If the file does NOT start with `---\n`, treats the whole file as body and decodes
///   an empty frontmatter (caller's `T` must support init from `{}`).
/// - If `---\n` opens but no closing `\n---\n` is found, throws `LoadError.malformedEnvelope`.
enum AtomicYAMLMarkdownError: LocalizedError {
    case utf8EncodingFailed
    case nonMappingFrontmatter
    var errorDescription: String? {
        switch self {
        case .utf8EncodingFailed:
            return "Failed to encode YAML frontmatter as UTF-8 — file not written."
        case .nonMappingFrontmatter:
            return
                "Cannot stamp a Class onto a file whose frontmatter root is not a "
                + "key/value mapping (it parses as a sequence or scalar). The file "
                + "was left unchanged to avoid destroying its existing frontmatter."
        }
    }
}

enum AtomicYAMLMarkdown {

    enum LoadError: Error, Equatable {
        case malformedEnvelope
    }

    static func load<T: Codable>(_ type: T.Type, from url: URL) throws -> (T, String) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fmText, body) = try split(raw)
        let frontmatter: T
        if fmText.isEmpty {
            // Decode from "{}" so Decodable types with all-optional fields succeed
            frontmatter = try YAMLDecoder().decode(T.self, from: "{}")
        } else {
            frontmatter = try YAMLDecoder().decode(T.self, from: fmText)
        }
        return (frontmatter, body)
    }

    static func write<T: Codable>(frontmatter: T, body: String, to url: URL) throws {
        let data = try encode(frontmatter: frontmatter, body: body)
        try data.write(to: url, options: [.atomic])
    }

    /// Encodes a frontmatter + body pair into the YAML-envelope `Data` shape
    /// that `write` persists. Exposed for callers (e.g. SchemaTransaction
    /// staging) that need to batch a Page write into a multi-file atomic
    /// commit: encode here, stage the returned Data via
    /// `SchemaTransaction.stage(payload:to:)`.
    static func encode<T: Codable>(frontmatter: T, body: String) throws -> Data {
        let fmText = try YAMLEncoder().encode(frontmatter)
        return try envelope(fmText, body)
    }

    // MARK: - Preserving overloads (foreign-key retaining, order-stable)

    /// Order-preserving, clear-aware `write`. Re-serializes the typed frontmatter
    /// but merges it over the EXISTING on-disk frontmatter at `existing` so that
    /// foreign keys (plugin / non-modeled frontmatter Pommora doesn't own) survive
    /// the round-trip and existing key order is held stable. A modeled key that is
    /// absent from the typed YAML (e.g. a cleared `encodeIfPresent` field) is
    /// dropped. New typed keys the existing file lacked append after.
    ///
    /// `modeledKeys` is the set of top-level keys this frontmatter type owns
    /// (`T.modeledKeys` via the `static modeledKeys` convention). When `existing`
    /// is nil / absent / has empty frontmatter, falls back to the plain `encode`
    /// path — byte-identical to a fresh write (no regression for new files).
    static func write<T: Codable>(
        frontmatter: T, body: String, to url: URL,
        preservingFrom existing: URL?, modeledKeys: Set<String>
    ) throws {
        let data = try mergedData(
            frontmatter: frontmatter, body: body,
            preservingFrom: existing, modeledKeys: modeledKeys)
        try data.write(to: url, options: [.atomic])
    }

    /// Order-preserving, clear-aware `encode -> Data`. Same merge semantics as the
    /// preserving `write`; for callers staging the payload into a multi-file
    /// `SchemaTransaction` rather than writing directly.
    static func encode<T: Codable>(
        frontmatter: T, body: String,
        preservingFrom existing: URL?, modeledKeys: Set<String>
    ) throws -> Data {
        try mergedData(
            frontmatter: frontmatter, body: body,
            preservingFrom: existing, modeledKeys: modeledKeys)
    }

    /// Shared merge envelope behind both preserving overloads. Reads the existing
    /// file's frontmatter as an ordered YAML mapping, rebuilds it preserving
    /// original key order, substitutes modeled keys with their typed values
    /// (dropping modeled keys absent from the typed YAML — the "cleared" path),
    /// passes foreign keys through untouched, then appends any typed keys the
    /// existing file lacked. Order relies on `Yams.serialize(sortKeys: false)`.
    private static func mergedData<T: Codable>(
        frontmatter: T, body: String, preservingFrom existing: URL?, modeledKeys: Set<String>
    ) throws -> Data {
        let typedYAML = try YAMLEncoder().encode(frontmatter)
        guard let existing, let raw = try? String(contentsOf: existing, encoding: .utf8),
            let (fm, _) = try? split(raw), !fm.isEmpty,
            case .mapping(let existingMap)? = try? Yams.compose(yaml: fm),
            case .mapping(let typedMap)? = try? Yams.compose(yaml: typedYAML)
        else { return try envelope(typedYAML, body) }

        var merged = Yams.Node.Mapping([])  // ([]) — no nullary init in Yams 5.4.0
        for (k, v) in existingMap {
            guard let key = k.string else {
                merged[k] = v
                continue
            }
            if modeledKeys.contains(key) {
                if let tv = typedMap[k] { merged[k] = tv } /* else cleared → drop */
            } else {
                merged[k] = v
            }
        }
        for (k, v) in typedMap where merged[k] == nil { merged[k] = v }
        return try envelope(try Yams.serialize(node: .mapping(merged)), body)
    }

    /// YAML-level single-key set that stamps the `Class:` discriminator onto a file
    /// without touching any other frontmatter. Value-preserving: reads existing
    /// frontmatter as a mapping, sets only the `Class` key, re-serializes. A
    /// frontmatter-less file gains ONLY `Class:` (no id / tier / properties
    /// injected). Idempotent — re-running produces identical output. The literal
    /// `"Class"` key is independent of any typed `kind` property.
    static func setStampKey(at url: URL, value: String) throws {
        let (fm, body) = try split(try String(contentsOf: url, encoding: .utf8))
        // Resolve the mapping to stamp onto:
        //   • empty / null / unparseable frontmatter → fresh mapping (create path,
        //     matches the frontmatter-less behavior of just adding `Class:`),
        //   • frontmatter that parses to a mapping → use it,
        //   • NON-EMPTY frontmatter that parses to a non-mapping (sequence / scalar)
        //     → throw and write nothing, so we never clobber existing content.
        let composed = try? Yams.compose(yaml: fm)
        var map: Yams.Node.Mapping
        switch composed {
        case .mapping(let m):
            map = m
        case .none:
            // Empty or whitespace-only frontmatter → create a fresh mapping.
            map = .init([])
        case .some(let node) where node.null != nil:
            // A frontmatter that composes to `null` (e.g. `~`) is treated like
            // empty — take the create-fresh path rather than throwing.
            map = .init([])
        default:
            // Non-empty frontmatter that is a sequence or a non-null scalar:
            // refuse to write so the existing content is never destroyed.
            throw AtomicYAMLMarkdownError.nonMappingFrontmatter
        }
        map[Yams.Node("Class")] = Yams.Node(value)
        try envelope(try Yams.serialize(node: .mapping(map)), body)
            .write(to: url, options: [.atomic])
    }

    // MARK: - Envelope

    /// Wraps a frontmatter YAML string + body into the canonical
    /// `---\n<fm>---\n\n<body>` envelope `Data`. `YAMLEncoder`/`Yams.serialize`
    /// emit a trailing newline on `fmText`, so the closing fence sits on its own
    /// line; the single blank line after it is the body separator that `split`
    /// strips on read. Single source of truth for the on-disk shape.
    private static func envelope(_ fmText: String, _ body: String) throws -> Data {
        let combined = "---\n\(fmText)---\n\n\(body)"
        guard let data = combined.data(using: .utf8) else {
            throw AtomicYAMLMarkdownError.utf8EncodingFailed
        }
        return data
    }

    // MARK: - Internal split

    /// Returns (frontmatter YAML string without fences, body string).
    /// If no envelope, returns ("", entire content).
    static func split(_ raw: String) throws -> (String, String) {
        guard raw.hasPrefix("---\n") else {
            return ("", raw)
        }
        // Strip leading "---\n"
        let afterOpening = raw.dropFirst(4)
        // Find closing "\n---\n"
        guard let closingRange = afterOpening.range(of: "\n---\n") else {
            throw LoadError.malformedEnvelope
        }
        let fm = String(afterOpening[..<closingRange.lowerBound])
        // Strip the single blank-line separator that `write` inserts between the
        // closing fence and the body. Matches write's `---\n\n<body>` format so
        // round-trips are exact.
        var body = String(afterOpening[closingRange.upperBound...])
        if body.hasPrefix("\n") {
            body.removeFirst()
        }
        return (fm, body)
    }
}
