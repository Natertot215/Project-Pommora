import SwiftUI

/// Bridges sidebar selection (a `PageMeta`) to a live `PageEditorViewModel`.
///
/// Responsibilities:
/// - Resolve the Page's parent Vault + Collection (so `ContentManagerPageSaver`
///   can route to the right `updatePage` variant).
/// - Load the Page's body from disk via `PageFile.load`.
/// - On selection change to a different Page, flush the previous VM's pending
///   debounce SYNCHRONOUSLY before constructing a new VM — prevents lost
///   edits during fast sidebar navigation.
///
/// Uses `.task(id: page.id)` for the lifecycle: SwiftUI cancels and re-runs the
/// task whenever the keyed id changes, giving us a clean spot to await the
/// close() of the outgoing VM.
struct PageEditorHost: View {
    let page: PageMeta

    @Environment(ContentManager.self) private var contentManager
    @Environment(PageTypeManager.self) private var vaultManager

    @State private var viewModel: PageEditorViewModel?
    @State private var resolvedVault: PageType?
    @State private var resolvedCollection: Pommora.Collection?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let vm = viewModel, let vault = resolvedVault {
                PageEditorView(viewModel: vm, vault: vault, collection: resolvedCollection)
                    // Force a full teardown + rebuild of PageEditorView when
                    // the loaded Page changes — guarantees @State (titleDraft)
                    // resets cleanly per-page and that the body editor
                    // re-init's its internal state without carrying over body.
                    .id(vm.page.id)
            } else if loadFailed {
                ContextDetailPlaceholder(
                    title: page.title,
                    icon: "exclamationmark.triangle",
                    accent: nil,
                    supportingLine: "Couldn't load this Page from disk."
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: page.id) {
            // Selection changed to a different Page: flush the outgoing VM
            // BEFORE constructing the new one. close() awaits flushNow() which
            // cancels the debounce and writes the current body to disk.
            if let outgoing = viewModel, outgoing.page.id != page.id {
                await outgoing.close()
            }
            await loadAndConstruct(for: page)
        }
    }

    private func loadAndConstruct(for page: PageMeta) async {
        guard let resolved = contentManager.resolveParent(for: page, pageTypeManager: vaultManager)
        else {
            viewModel = nil
            resolvedVault = nil
            resolvedCollection = nil
            loadFailed = true
            return
        }

        // Lenient load is the editor's canonical path: matches the sidebar's
        // discovery contract (ContentManager.loadAll → PageFile.loadLenient)
        // so any adopted `.md` file that surfaces in the sidebar also opens
        // in the editor. Files without Pommora frontmatter get a synthesized
        // path-stable id; the on-disk file isn't mutated until the user
        // edits and saves.
        // (File I/O on the main actor is fine at v1 prose sizes; if we later
        // need to keep the main thread free, make the loader nonisolated
        // rather than hopping off via Task.detached.)
        guard
            let pageFile = try? PageFile.loadLenient(
                from: page.url,
                nexusRoot: contentManager.nexus.rootURL
            )
        else {
            viewModel = nil
            resolvedVault = nil
            resolvedCollection = nil
            loadFailed = true
            return
        }

        let saver = ContentManagerPageSaver(
            contentManager: contentManager,
            vault: resolved.vault,
            collection: resolved.collection
        )
        let vm = PageEditorViewModel(page: page, body: pageFile.body, saver: saver)
        viewModel = vm
        resolvedVault = resolved.vault
        resolvedCollection = resolved.collection
        loadFailed = false
    }
}
