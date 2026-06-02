import CryptoKit
import Foundation
import Yams

/// Composite of frontmatter + body for a `.md` Page file.
/// I/O via `AtomicYAMLMarkdown`. Title derived from filename on load.
struct PageFile: Equatable, Sendable {
    var frontmatter: PageFrontmatter
    var body: String
    var title: String  // derived from filename on load; not persisted

    init(frontmatter: PageFrontmatter, body: String, title: String = "") {
        self.frontmatter = frontmatter
        self.body = body
        self.title = title
    }

    static func load(from url: URL) throws -> PageFile {
        let (fm, body): (PageFrontmatter, String) =
            try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: url)
        return PageFile(
            frontmatter: fm,
            body: body,
            title: url.deletingPathExtension().lastPathComponent
        )
    }

    func save(to url: URL) throws {
        // Preserving write: merge over the file already at `url` so foreign
        // (plugin) frontmatter survives and key order stays stable. A brand-new
        // Page (no file at `url` yet) falls back to a plain envelope — identical
        // bytes to a fresh write.
        try AtomicYAMLMarkdown.write(
            frontmatter: frontmatter, body: body, to: url,
            preservingFrom: url, modeledKeys: PageFrontmatter.modeledKeys)
    }

    /// Tolerant counterpart to `load(from:)` used by the folder-adoption flow.
    /// Accepts `.md` files that lack Pommora frontmatter — synthesizes a stable
    /// `id` from the file's path relative to the Nexus root, defaults missing
    /// tier/properties to empty, and uses the file's creation date for
    /// `created_at` when absent.
    ///
    /// Does NOT write back. The on-disk file stays byte-identical until the
    /// user actually edits and saves the Page through the editor.
    static func loadLenient(from url: URL, nexusRoot: URL) throws -> PageFile {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (fmText, body) = (try? AtomicYAMLMarkdown.split(raw)) ?? ("", raw)

        let shape: LenientFrontmatterShape
        if fmText.isEmpty {
            shape = LenientFrontmatterShape()
        } else {
            shape =
                (try? YAMLDecoder().decode(LenientFrontmatterShape.self, from: fmText))
                ?? LenientFrontmatterShape()
        }

        let relativePath = Self.relativePath(of: url, under: nexusRoot)
        let synthesizedID = "adopted-" + Self.shortHash(of: relativePath)
        let fileCreatedAt =
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

        let fm = PageFrontmatter(
            id: shape.id ?? synthesizedID,
            icon: shape.icon,
            tier1: shape.tier1 ?? [],
            tier2: shape.tier2 ?? [],
            tier3: shape.tier3 ?? [],
            properties: shape.properties ?? [:],
            createdAt: shape.createdAt ?? fileCreatedAt
        )

        return PageFile(
            frontmatter: fm,
            body: body,
            title: url.deletingPathExtension().lastPathComponent
        )
    }

    // MARK: - Lenient helpers

    /// Shape that accepts a `.md` file with missing or partial Pommora
    /// frontmatter. Every field is optional; consumers (only
    /// `PageFile.loadLenient`) fill in synthesized defaults.
    private struct LenientFrontmatterShape: Codable {
        var id: String?
        var icon: String?
        var tier1: [String]?
        var tier2: [String]?
        var tier3: [String]?
        var properties: [String: PropertyValue]?
        var createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, icon, tier1, tier2, tier3, properties
            case createdAt = "created_at"
        }
    }

    private static func relativePath(of url: URL, under nexusRoot: URL) -> String {
        let standardisedURL = url.standardizedFileURL.path
        let standardisedRoot = nexusRoot.standardizedFileURL.path
        let prefix = standardisedRoot.hasSuffix("/") ? standardisedRoot : standardisedRoot + "/"
        if standardisedURL.hasPrefix(prefix) {
            return String(standardisedURL.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    private static func shortHash(of string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return
            digest
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .lowercased()
    }
}
