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
    var errorDescription: String? {
        "Failed to encode YAML frontmatter as UTF-8 — file not written."
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
        let fmText = try YAMLEncoder().encode(frontmatter)
        let combined = "---\n\(fmText)---\n\n\(body)"
        guard let data = combined.data(using: .utf8) else {
            throw AtomicYAMLMarkdownError.utf8EncodingFailed
        }
        try data.write(to: url, options: [.atomic])
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
