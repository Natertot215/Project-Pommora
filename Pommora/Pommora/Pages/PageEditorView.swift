import MarkdownEditor
import SwiftUI

/// The Page editor surface: WKWebView (via MarkdownEditor SPM) + inspector
/// side panel + lifecycle registration with AppGlobals for background-flush.
///
/// The body↔WebView binding is two-way per Pallepadehat's EditorWebView:
/// every keystroke updates `viewModel.body` via the binding; that `didSet`
/// fires `scheduleSave()` which debounces 300ms then writes to disk via
/// `ContentManager.updatePage` → `PageFile.save` → atomic write. Frontmatter
/// is preserved verbatim across every save.
struct PageEditorView: View {
    @State var viewModel: PageEditorViewModel
    let vault: Vault

    /// Per-pageID open flag, loaded from AppState on init and persisted on toggle.
    @State private var inspectorOpen: Bool

    init(viewModel: PageEditorViewModel, vault: Vault) {
        self.viewModel = viewModel
        self.vault = vault
        // Initial state from disk; if the file/key is missing we default closed.
        self._inspectorOpen = State(
            initialValue: AppState.pageInspectorOpen(pageID: viewModel.page.id)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title banner — read-only "filename = title" display, matching
            // macOS Notes' large title line. Rename happens via sidebar
            // right-click → Rename (already wired).
            Text(viewModel.page.title)
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 4)
                .textSelection(.enabled)

            EditorWebView(text: $viewModel.body, configuration: pommoraEditorConfig)
        }
        .inspector(isPresented: $inspectorOpen) {
            FrontmatterInspector(page: viewModel.page, vault: vault)
                .inspectorColumnWidth(min: 240, ideal: 320, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        inspectorOpen.toggle()
                    }
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("0", modifiers: [.option, .command])
                .help("Toggle Inspector (⌥⌘0)")
            }
        }
        .onChange(of: inspectorOpen) { _, newValue in
            AppState.setPageInspectorOpen(newValue, pageID: viewModel.page.id)
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
