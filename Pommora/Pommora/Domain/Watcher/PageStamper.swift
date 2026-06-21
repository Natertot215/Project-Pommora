import Foundation

/// Mints and persists a stable ULID into a `.md` Page that lacks one — a file
/// authored outside Pommora (Obsidian, vim, Finder). A persisted id is what lets
/// an external rename be tracked as the same entity instead of delete-plus-create.
/// The write is additive: foreign frontmatter survives via the atomic preserving
/// write, and only the `id` line is introduced.
enum PageStamper {

    /// `PageFile.loadLenient`'s placeholder-id prefix for a frontmatter-less file.
    /// Its presence means no real id is on disk yet.
    private static let synthesizedPrefix = "adopted-"

    /// Stamps an already-loaded Page that lacks a real id, persisting a ULID into
    /// its frontmatter, and returns the (possibly updated) value. Idempotent. The
    /// index build uses this so its snapshot carries the persisted id without a
    /// second read.
    static func stampInPlace(_ page: PageFile, at url: URL) -> PageFile {
        guard page.frontmatter.id.hasPrefix(synthesizedPrefix) else { return page }
        var stamped = page
        stamped.frontmatter.id = ULID.generate()
        // Adopt the new id only if it actually persisted — a failed write must
        // leave the caller with the original (deterministic) id, not a random one
        // the on-disk file doesn't carry.
        guard (try? stamped.save(to: url)) != nil else { return page }
        return stamped
    }

    /// Stamps the Page at `url` if it has no real id. Idempotent — a Page already
    /// carrying a ULID is left byte-identical. Returns whether it wrote.
    @discardableResult
    static func stampIfNeeded(at url: URL, nexusRoot: URL) -> Bool {
        guard let page = try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot)
        else { return false }
        return stampInPlace(page, at: url).frontmatter.id != page.frontmatter.id
    }
}
