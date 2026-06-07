import Foundation

/// Single source of truth for "resolve an entity's `.md` file URL from its index
/// container". Page + Item managers delegate their private locators here, and
/// ConnectionCascade uses it directly (it rewrites both page and item sources).
enum ConnectionFileLocator {
    static func locate(id: String, kind: EntityKind, container: EntityContainer, nexusRoot: URL) -> URL? {
        let folder: URL
        switch kind {
        case .page:
            folder = container.collectionTitle.map {
                NexusPaths.pageCollectionFolderURL(in: nexusRoot, typeFolderName: container.typeTitle, collectionFolderName: $0)
            } ?? NexusPaths.pageTypeFolderURL(in: nexusRoot, typeFolderName: container.typeTitle)
        case .item:
            folder = container.collectionTitle.map {
                NexusPaths.itemCollectionFolderURL(in: nexusRoot, typeFolderName: container.typeTitle, collectionFolderName: $0)
            } ?? NexusPaths.itemTypeFolderURL(in: nexusRoot, typeFolderName: container.typeTitle)
        default:
            return nil
        }
        let candidate: URL = kind == .page
            ? NexusPaths.pageFileURL(forTitle: container.entityTitle, in: folder)
            : NexusPaths.itemFileURL(forTitle: container.entityTitle, in: folder)
        if Filesystem.fileExists(at: candidate), idMatches(candidate, id: id, kind: kind, nexusRoot: nexusRoot) { return candidate }
        let matches = (try? Filesystem.descendantFiles(of: folder) { url in
            url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
        }) ?? []
        return matches.first { idMatches($0, id: id, kind: kind, nexusRoot: nexusRoot) }
    }

    /// Check whether a `.md` file's stored (or synthesized) ID matches `id`.
    /// Uses lenient loading for pages so adopted files without full Pommora
    /// frontmatter are matched via their path-stable synthesized ID.
    private static func idMatches(_ url: URL, id: String, kind: EntityKind, nexusRoot: URL) -> Bool {
        switch kind {
        case .page:
            return (try? PageFile.loadLenient(from: url, nexusRoot: nexusRoot).frontmatter.id) == id
        case .item:
            return (try? Item.load(from: url).id) == id
        default:
            return false
        }
    }
}
