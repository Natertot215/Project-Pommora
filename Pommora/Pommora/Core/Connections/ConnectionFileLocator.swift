import Foundation

/// Single source of truth for "resolve a Page's `.md` file URL from its index
/// container". PageContentManager delegates its private locator here, and
/// ConnectionCascade uses it directly (it rewrites page sources).
enum ConnectionFileLocator {
    static func locate(id: String, kind: EntityKind, container: EntityContainer, nexusRoot: URL) -> URL? {
        let folder: URL
        switch kind {
        case .page:
            folder = NexusPaths.pageTypeFolderURL(in: nexusRoot, typeFolderName: container.typeTitle)
        case .agendaTask, .agendaEvent, .pageCollection, .pageSet, .area, .topic, .project:
            return nil
        }
        let candidate = NexusPaths.pageFileURL(forTitle: container.entityTitle, in: folder)
        if Filesystem.fileExists(at: candidate), idMatches(candidate, id: id, nexusRoot: nexusRoot) { return candidate }
        let matches = (try? Filesystem.descendantFiles(of: folder) { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
        }) ?? []
        return matches.first { idMatches($0, id: id, nexusRoot: nexusRoot) }
    }

    /// Check whether a `.md` file's stored (or synthesized) ID matches `id`.
    /// Uses lenient loading so adopted files without full Pommora frontmatter
    /// are matched via their path-stable synthesized ID.
    private static func idMatches(_ url: URL, id: String, nexusRoot: URL) -> Bool {
        (try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot).frontmatter.id) == id
    }
}
