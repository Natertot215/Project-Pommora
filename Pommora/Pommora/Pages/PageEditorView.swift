import AppKit
import MarkdownEngine
import SwiftUI

/// The Page editor surface: editable title banner above the body editor.
/// The inspector + its toolbar toggle live in ContentView (not here) so the
/// inspector renders at the window's trailing edge rather than inside this
/// sub-view's space.
///
/// Title is editable in place: a TextField visually matched to macOS Notes'
/// large title line. Committing the field (Enter / focus loss) calls
/// `ContentManager.renamePage` which moves the on-disk `.md` file and
/// updates the in-memory caches. The viewModel.page reference is refreshed
/// with the post-rename PageMeta so subsequent saves hit the new URL.
///
/// The body editor is `NativeTextViewWrapper` from the locally-vendored
/// `MarkdownEngine` package (External/MarkdownEngine/). Every keystroke
/// updates `viewModel.body` via Binding; `didSet` fires `scheduleSave()`
/// which debounces 300ms then writes via `ContentManager.updatePage` →
/// `PageFile.save` → atomic write. Frontmatter is preserved verbatim across
/// every save.
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
    /// SwiftUI-side focus state for the title TextField. Pressing Enter
    /// flips this off, which deselects the title and lets us hand focus
    /// over to the body NSTextView (which doesn't participate in SwiftUI's
    /// FocusState graph — we makeFirstResponder it directly).
    @FocusState private var titleFocused: Bool

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
                .padding(.bottom, 20)
                .background(Color.clear)
                .focused($titleFocused)
                .onSubmit {
                    // Drop SwiftUI focus FIRST so the title field deselects
                    // (otherwise macOS NSTextField's default Enter behavior
                    // is to select-all). Then move AppKit firstResponder to
                    // the body editor. Rename runs in parallel — doesn't
                    // need to block focus shift.
                    titleFocused = false
                    focusBodyEditor()
                    Task { await commitRename() }
                }

            // Body editor — TextKit-2 native via vendored MarkdownEngine.
            // The wrapper binds two-way to viewModel.body; every keystroke
            // flows through the VM's 300ms debounced save pipeline.
            // documentId scoped per-Page so undo history + per-document
            // editor state stay isolated when the user switches Pages.
            //
            // TextInsets(horizontal: 24) aligns body text with the title's
            // .padding(.horizontal, 24). Applied INSIDE the NSTextView
            // (textContainerInset) rather than as SwiftUI padding so the
            // scrollbar stays at the outer edge.
            NativeTextViewWrapper(
                text: $viewModel.body,
                configuration: Self.pommoraEditorConfiguration,
                fontName: "SF Pro Text",
                fontSize: 15,
                documentId: viewModel.page.id
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Pommora's editor configuration. Text insets match the title's 24pt
    /// horizontal padding so body content aligns under the title rather
    /// than butting against the sidebar divider.
    private static let pommoraEditorConfiguration: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration.default
        config.textInsets = TextInsets(horizontal: 24, vertical: 0)
        return config
    }()

    /// Move focus from the title TextField to the body NSTextView. Walks
    /// the key window's view tree to find the first NSTextView (which is
    /// the body editor — the sidebar uses NSTextField, not NSTextView)
    /// and makes it firstResponder. Dispatched async so the title's
    /// onSubmit rename round-trip completes first.
    private func focusBodyEditor() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow,
                let contentView = window.contentView,
                let bodyEditor = Self.findFirstTextView(in: contentView)
            else { return }
            window.makeFirstResponder(bodyEditor)
        }
    }

    private static func findFirstTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for subview in view.subviews {
            if let found = findFirstTextView(in: subview) { return found }
        }
        return nil
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
