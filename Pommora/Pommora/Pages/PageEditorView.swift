import MarkdownEditor
import SwiftUI

/// The Page editor surface: editable title banner above WKWebView. The
/// inspector + its toolbar toggle live in ContentView (not here) so the
/// inspector renders at the window's trailing edge rather than inside this
/// sub-view's space.
///
/// Title is editable in place: a TextField visually matched to macOS Notes'
/// large title line. Committing the field (Enter / focus loss) calls
/// `ContentManager.renamePage` which moves the on-disk `.md` file and
/// updates the in-memory caches. The viewModel.page reference is refreshed
/// with the post-rename PageMeta so subsequent saves hit the new URL.
///
/// The body↔WebView binding is two-way per Pallepadehat's EditorWebView:
/// every keystroke updates `viewModel.body` via the binding; `didSet` fires
/// `scheduleSave()` which debounces 300ms then writes via
/// `ContentManager.updatePage` → `PageFile.save` → atomic write. Frontmatter
/// is preserved verbatim across every save.
struct PageEditorView: View {
    // @Bindable (not @State) because the VM is owned by PageEditorHost; this
    // view observes + binds to it without taking ownership. @State on a
    // received-from-parent reference preserves the OLD reference across
    // re-renders — the v0.2.7-c5 regression that broke sidebar page switching.
    @Bindable var viewModel: PageEditorViewModel
    let vault: Vault
    /// nil = vault-root Page (no Collection parent)
    let collection: Pommora.Collection?

    @Environment(ContentManager.self) private var contentManager

    /// In-flight title text. Synced with `viewModel.page.title` on every
    /// page-id change (the `.onChange(initial: true)` below) — but the host
    /// also re-keys this view via `.id(viewModel.page.id)`, so the @State is
    /// freshly init'd per page anyway. The onChange handler is the belt; the
    /// .id() is the suspenders.
    @State private var titleDraft: String

    init(
        viewModel: PageEditorViewModel,
        vault: Vault,
        collection: Pommora.Collection?
    ) {
        self.viewModel = viewModel
        self.vault = vault
        self.collection = collection
        self._titleDraft = State(initialValue: viewModel.page.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title banner — editable; matches macOS Notes' large title line.
            // Submitting renames the on-disk .md file via ContentManager.renamePage.
            TextField("Untitled", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 4)
                .onSubmit {
                    Task { await commitRename() }
                }

            EditorWebView(text: $viewModel.body, configuration: pommoraEditorConfig)
        }
        .onAppear {
            AppGlobals.register(viewModel)
        }
        .onDisappear {
            AppGlobals.unregister(viewModel)
            // Flush any pending debounced save before the view goes away.
            let vmRef = viewModel
            Task { await vmRef.close() }
        }
        .onChange(of: viewModel.page.id, initial: true) { _, _ in
            // Belt: if the host re-uses this view for a different Page (e.g.,
            // .id() doesn't trigger a full rebuild), resync the draft title.
            titleDraft = viewModel.page.title
        }
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { viewModel.pendingError != nil },
                set: { newValue in
                    if !newValue { viewModel.clearError() }
                }
            )
        ) {
            Button("Retry") {
                viewModel.explicitSave()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.pendingError?.localizedDescription ?? "")
        }
    }

    private func commitRename() async {
        let oldTitle = viewModel.page.title
        let newTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        // No-op on unchanged or empty input. Empty reverts to current title.
        guard !newTitle.isEmpty else {
            titleDraft = oldTitle
            return
        }
        guard newTitle != oldTitle else { return }

        do {
            if let collection {
                try await contentManager.renamePage(
                    viewModel.page, to: newTitle, in: collection, vault: vault
                )
            } else {
                try await contentManager.renamePage(
                    viewModel.page, to: newTitle, inVaultRoot: vault
                )
            }
            // Pick up the freshly-renamed PageMeta from the manager cache.
            let updated: PageMeta?
            if let collection {
                updated = contentManager.pages(in: collection).first {
                    $0.id == viewModel.page.id
                }
            } else {
                updated = contentManager.pages(in: vault).first {
                    $0.id == viewModel.page.id
                }
            }
            if let updated {
                viewModel.page = updated
                titleDraft = updated.title
            }
        } catch {
            viewModel.pendingError = error
            titleDraft = oldTitle
        }
    }
}

/// Pommora's editor configuration. Live Preview (`hideSyntax: true`), prose
/// font instead of monospace, line numbers off (Pages are prose, not code).
private let pommoraEditorConfig = EditorConfiguration(
    fontSize: 15,
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif",
    lineHeight: 1.55,
    showLineNumbers: false,
    wrapLines: true,
    renderMermaid: true,
    renderMath: true,
    renderImages: true,
    hideSyntax: true
)
