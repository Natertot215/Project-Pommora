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
    let vault: PageType
    /// nil = vault-root Page (no Collection parent)
    let collection: PageCollection?
    /// Navigate the sidebar selection (breadcrumb crumb clicks route here).
    let onNavigate: (SidebarSelection) -> Void

    @Environment(PageContentManager.self) private var contentManager

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
    /// Normalized scroll offset of the body editor's scroll view (0 at rest,
    /// positive while scrolled down). Drives the title overlay's `.offset`
    /// so the title scrolls in sync with body content — at-rest the title
    /// sits over the body's reserved top safe-area; scrolling moves it
    /// upward off-screen. The body editor's `safeAreaInsets.top` equals
    /// `titleAreaHeight` so body content visually butts the title-area
    /// divider at rest.
    @State private var scrollOffset: CGFloat = 0

    /// Whether the bottom stats footer is expanded. A global app preference
    /// (UserDefaults via `@AppStorage`), so on/off persists across every Page
    /// and across launches — not per-document. The toggle chevron is an editor
    /// overlay (outside `PageStatsBar`), so the bar holds only the counts row.
    @AppStorage("pageStatsFooterExpanded") private var statsExpanded = false
    /// Latest computed document statistics, shown while the footer is open.
    /// Set synchronously on open (instant counts) and refreshed debounced as
    /// the body changes.
    @State private var stats = PageTextStats.empty
    /// Cursor is over the chevron's hover zone — drives chevron visibility in
    /// both collapsed and expanded states (the chevron is hover-gated like the
    /// heading-fold chevron).
    @State private var hoveringChevron = false
    /// True for the first 3 s after expanding, then false — keeps the collapse
    /// chevron briefly visible on open before it goes hover-only.
    @State private var chevronForcedVisible = false

    /// Top padding of the body editor's text container, sized to leave room
    /// for the title overlay + a 14pt equidistant gap below the divider.
    /// Natural title height: `padding(.top, 24)` + 28pt bold TextField line
    /// (~34pt) + `padding(.bottom, 14)` + 1pt Divider ≈ 73pt. Add 14pt gap +
    /// a small safety margin → 90pt.
    ///
    /// Used in two places that MUST agree:
    ///   1. The body editor's `textInsets.vertical` (reserves the empty zone
    ///      at the top of the text container — this scrolls with body
    ///      content unlike `safeAreaInsets`, which is a fixed scroll-view
    ///      padding that doesn't move on scroll).
    ///   2. The `.offset(y: -min(scrollOffset, titleAreaHeight))` clamp on
    ///      the title overlay (lets the overlay scroll up off-screen and
    ///      stay there once fully scrolled past).
    private static let titleAreaHeight: CGFloat = 90

    init(
        viewModel: PageEditorViewModel,
        vault: PageType,
        collection: PageCollection?,
        onNavigate: @escaping (SidebarSelection) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.vault = vault
        self.collection = collection
        self.onNavigate = onNavigate
        self._titleDraft = State(initialValue: viewModel.page.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            // PropertiesPulldown removed 2026-05-25 per Nathan's directive —
            // it obstructed the titlebar and isn't needed on the Page editor.
            // Properties for Pages will live in the Claude chat main-window
            // inspector slot when that ships (v0.3.x per Framework.md).
            // FrontmatterInspector still surfaces page properties via the
            // pop-out inspector pane when explicitly opened.
            editorZStack
                .overlay(alignment: .bottomTrailing) { statsChevron }

            if statsExpanded {
                Divider()
                PageStatsBar(
                    vault: vault,
                    collection: collection,
                    page: viewModel.page,
                    stats: stats,
                    onNavigate: onNavigate
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Recompute debounced while the footer is open: any body keystroke (or
        // the open itself) restarts this task, so the 250ms sleep coalesces
        // rapid edits before the single re-parse.
        .task(id: StatsRecomputeKey(expanded: statsExpanded, body: viewModel.body)) {
            guard statsExpanded else { return }
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { stats = PageTextStats(body: viewModel.body) }
        }
        // On open, force the chevron visible for 3s, then let it go hover-only.
        .task(id: statsExpanded) {
            guard statsExpanded else { chevronForcedVisible = false; return }
            chevronForcedVisible = true
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { chevronForcedVisible = false }
        }
        // Page opened with the footer already on (persisted preference): compute
        // counts immediately so the bar doesn't flash empty before the debounce.
        .onAppear {
            if statsExpanded { stats = PageTextStats(body: viewModel.body) }
        }
    }

    /// Equatable key that restarts the debounced stats recompute when either the
    /// footer's open-state or the body text changes.
    private struct StatsRecomputeKey: Equatable {
        let expanded: Bool
        let body: String
    }

    /// Toggle chevron — an editor overlay (outside `PageStatsBar`) so it floats
    /// over the editor's bottom-right corner in both states without adding to
    /// the bar's height. Hover-gated: the (always-present, transparent) hit
    /// zone reveals the glyph on hover; on open it's briefly forced visible.
    private var statsChevron: some View {
        let visible = hoveringChevron || chevronForcedVisible
        return Button {
            if !statsExpanded {
                // Compute synchronously so counts show instantly on open; the
                // debounced task keeps them fresh thereafter.
                stats = PageTextStats(body: viewModel.body)
            }
            withAnimation(.easeInOut(duration: 0.22)) { statsExpanded.toggle() }
        } label: {
            Image(systemName: statsExpanded ? "chevron.compact.down" : "chevron.compact.up")
                .font(.title2)
                .foregroundStyle(.secondary)
                .opacity(visible ? 1 : 0)
                .frame(width: 48, height: 28)
                .contentShape(Rectangle())
                .onHover { hoveringChevron = $0 }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .padding(.trailing, 16)
        // Snug above the bar when open; comfortably inset from the window edge
        // when collapsed.
        .padding(.bottom, statsExpanded ? 4 : 12)
        .accessibilityLabel(statsExpanded ? "Hide statistics" : "Show statistics")
    }

    private var editorZStack: some View {
        ZStack(alignment: .topLeading) {
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
            //
            // `safeAreaInsets.top = titleAreaHeight` reserves the top
            // `titleAreaHeight` points of the scroll view for the title
            // overlay — at rest the body's first line sits immediately
            // below the title-area divider; the inset zone scrolls
            // naturally so the title can move up off-screen via offset.
            //
            // `onScrollOffsetChange` fires on every scroll-view bounds
            // change with the normalized scroll Y (0 at rest, positive
            // when scrolled down). We mirror it to `scrollOffset` so the
            // overlay can track it via `.offset`.
            NativeTextViewWrapper(
                text: $viewModel.body,
                foldedHeadings: $viewModel.foldedHeadings,
                configuration: Self.pommoraEditorConfiguration,
                fontName: "SF Pro Text",
                fontSize: 15,
                documentId: viewModel.page.id,
                onScrollOffsetChange: { newOffset in
                    if abs(scrollOffset - newOffset) > 0.5 {
                        scrollOffset = newOffset
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Title + divider overlay. Sits on top of the body editor's
            // reserved safe-area zone at rest. Tracks the body editor's
            // vertical scroll via `.offset(y: -scrollOffset)` so it scrolls
            // in sync with body content — when fully scrolled past, the
            // entire title region is off-screen above the viewport and the
            // body fills the visible area.
            //
            // Submitting renames the on-disk .md file via
            // ContentManager.renamePage. The 28pt bold matches macOS Notes'
            // large title line.
            VStack(spacing: 0) {
                TextField("Untitled", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 14)
                    .focused($titleFocused)
                    .onSubmit {
                        // Drop SwiftUI focus FIRST so the title field
                        // deselects (otherwise macOS NSTextField's default
                        // Enter behavior is to select-all). Then move
                        // AppKit firstResponder to the body editor. Rename
                        // runs in parallel — doesn't need to block focus
                        // shift.
                        titleFocused = false
                        focusBodyEditor()
                        Task { await commitRename() }
                    }

                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
            }
            .offset(y: -min(max(0, scrollOffset), Self.titleAreaHeight))
        }
        // Clip the ZStack so the title overlay's offset doesn't bleed up
        // past the editor's top edge into the toolbar region — SwiftUI's
        // `.offset` shifts rendering without clipping at the parent
        // boundary, so without this the title appears to "hit the top"
        // partially visible instead of fully disappearing on scroll.
        .clipped()
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

    /// Pommora's editor configuration. Horizontal text insets match the
    /// title's 24pt horizontal padding so body content aligns under the
    /// title rather than butting against the sidebar divider.
    ///
    /// Vertical inset = `titleAreaHeight` (90pt) reserves the top of the
    /// text container for the title overlay + 14pt gap below the divider.
    /// `textContainerInset` is INSIDE the documentView, so this empty zone
    /// scrolls naturally with body content as the user scrolls down —
    /// allowing the title overlay (positioned in SwiftUI ZStack coords) to
    /// track via `.offset(y: -scrollOffset)` and disappear off-screen in
    /// sync. (NSScrollView's `contentInsets` would NOT work here — those
    /// are fixed padding that doesn't scroll with content; the inset zone
    /// would stay at top while body slid behind a static overlay.)
    ///
    /// Symmetric: the bottom of the document gets the same 90pt padding
    /// above the scroll overscroll region. Trailing whitespace below the
    /// final body line is acceptable and matches the visual treatment most
    /// long-form editors use.
    private static let pommoraEditorConfiguration: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration.default
        config.textInsets = TextInsets(horizontal: 24, vertical: titleAreaHeight)
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
