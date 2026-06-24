import SwiftUI
import UniformTypeIdentifiers

/// Set / Change / Remove a Page's cover image. Hosts a `fileImporter([.image])`
/// and writes the chosen file's nexus-relative path onto the Page's `cover`
/// **root frontmatter field** via `PageContentManager.updatePageFrontmatter`
/// (NEVER `updatePageProperty` — `cover` is a frontmatter root key, not a
/// user property). Remove writes `cover = nil`.
///
/// Security-scope discipline (Swift-6-safe — the scope must NOT span the async
/// frontmatter write): in the importer completion we open the scope, `defer`
/// its close, copy the source synchronously-within-scope via `CoverAssetStore`
/// (the scoped read completes inside that window), then hop to a `Task` for the
/// async frontmatter write using the returned nexus-relative path.
///
/// Stateless host: the parent owns `isPresenting`; this view only wires the
/// importer + the three actions. The menu items are vended via `coverMenu` so
/// the card can place them in its cover-area context menu.
struct CoverPicker: View {
    let page: PageMeta
    let pageCollection: PageCollection
    let collection: PageSet?
    let set: PageSet?
    let nexus: Nexus
    @Binding var isPresenting: Bool

    @Environment(PageContentManager.self) private var contentManager

    var body: some View {
        // Invisible anchor; the parent toggles `isPresenting` from the cover
        // context menu and this importer fires.
        Color.clear
            .frame(width: 0, height: 0)
            .fileImporter(
                isPresented: $isPresenting,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let source = urls.first else { return }
                importCover(from: source)
            }
    }

    /// Copies the source into the page's assets folder inside the scoped window,
    /// then writes the nexus-relative path onto `cover`.
    ///
    /// The security-scoped READ of the source happens entirely inside
    /// `CoverAssetStore.storeSync` (a synchronous FileManager copy) BEFORE the
    /// `defer` closes the scope — so the scope never spans the async frontmatter
    /// write. Only the `cover` persistence hops to a `Task`.
    private func importCover(from source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let store = CoverAssetStore()
        let previousCover = page.frontmatter.cover
        let relativePath: String
        do {
            relativePath = try store.storeSync(image: source, for: page.id, in: nexus)
        } catch {
            // Copy failed inside the scoped window; surface via the manager's
            // pendingError so SidebarToast shows it (same toast path as the write).
            contentManager.pendingError = error
            return
        }

        // Scope-free async hop: persist the nexus-relative path onto `cover`.
        // The replaced cover file is deleted ONLY AFTER the write succeeds, so a
        // failed write never leaves `cover` pointing at a deleted file.
        var fm = page.frontmatter
        fm.cover = relativePath
        Task {
            do {
                try await contentManager.updatePageFrontmatter(
                    page, frontmatter: fm, pageCollection: pageCollection, collection: collection, set: set)
                store.delete(relativePath: previousCover, for: page.id, in: nexus)
            } catch {
                // pendingError on the manager surfaces a toast.
            }
        }
    }
}

/// Resolves a nexus-relative asset path (`.nexus/assets/<id>/<file>`) to a
/// `file://` URL under the nexus root. Single source of truth for cover +
/// banner URL resolution (DRY).
enum AssetURLResolver {
    static func fileURL(forRelativePath path: String, in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(path, isDirectory: false)
    }
}
