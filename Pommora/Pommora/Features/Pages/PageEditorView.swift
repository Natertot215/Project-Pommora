import AppKit
import MarkdownPM
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
/// The body editor is `MarkdownPMEditor` from the in-tree MarkdownPM
/// package (External/MarkdownPM/). Every keystroke
/// updates `viewModel.body` via Binding; `didSet` fires `scheduleSave()`
/// which debounces 300ms then writes via `ContentManager.updatePage` →
/// `PageFile.save` → atomic write. Frontmatter is preserved verbatim across
/// every save.
struct PageEditorView: View {
    // @Bindable (not @State) because the VM is owned by PageEditorHost; this
    // view observes + binds to it without taking ownership. @State on a
    // received-from-parent reference preserves the OLD reference across
    // re-renders, which breaks sidebar page switching.
    @Bindable var viewModel: PageEditorViewModel
    let vault: PageType
    /// nil = vault-root Page (no Collection parent)
    let collection: PageSet?
    /// nil = Page outside any Set. Non-nil implies `collection` is non-nil
    /// (Sets only live inside Collections); routes saves/renames through the
    /// Set-scoped overloads so the index row keeps its `page_set_id`.
    let set: PageSet?
    /// Drives breadcrumb back-navigation. Set by SidebarDetailView.
    @Binding var selection: SidebarSelection

    @Environment(PageContentManager.self) private var contentManager
    @Environment(PageSetManager.self) private var pageSetManager
    /// Routes a clicked `[[ ]]` page link into the main detail pane. Same router
    /// Navigation + Back/Forward use; injected by `NexusEnvironment`.
    @Environment(MainWindowRouter.self) private var mainWindowRouter
    /// Per-Nexus settings; gates the page-header icon + "Add Icon" affordance.
    @Environment(SettingsManager.self) private var settingsManager
    /// Stable title-keyed connection resolver injected by `NexusEnvironment`.
    /// Drives live `[[ ]]` styling; the editor config is rebuilt from it (the
    /// resolver INSTANCE stays stable, so the NSViewRepresentable doesn't
    /// churn per keystroke).
    @Environment(\.connectionResolver) private var connectionResolver

    /// In-flight title text. Synced with `viewModel.page.title` on every
    /// page-id change (the `.onChange(initial: true)` below) — but the host
    /// also re-keys this view via `.id(viewModel.page.id)`, so the @State is
    /// freshly init'd per page anyway. The onChange handler is the belt; the
    /// .id() is the suspenders.
    @State private var titleDraft: String
    /// True while the title is in inline-rename mode (entered via the header's
    /// right-click "Rename"); the title shows as static text otherwise.
    @State private var isRenamingTitle = false
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

    /// Drives the icon-picker popover, anchored on the page header; opened from
    /// the header's right-click "Change Icon" menu item.
    @State private var iconPickerOpen = false

    // MARK: - `[[` autocomplete

    /// Pushed into the editor to commit a chosen candidate: the engine replaces
    /// the active token with the finished link, restores the caret past it, then
    /// clears this binding.
    @State private var pendingInlineReplacement: InlineReplacementRequest?
    /// The inline token the caret is currently inside (kind + range/placeholder),
    /// captured on every valid trigger. `onSelect` reads its `.selection` to build
    /// the replacement request; `nil` when no autocomplete-eligible token is active.
    @State private var activeInlineSelection: InlineSelectionState?
    /// Live candidate list for the popup — mapped from the index `titleCandidates`
    /// query keyed off the in-bracket placeholder.
    @State private var autocompleteCandidates: [AutoCompleteCandidate] = []
    /// Caret rect in the body NSTextView's view coordinates (from
    /// `viewRect(forCharacterRange:)`). Anchors the popup just below the caret.
    @State private var caretRect: CGRect = .zero
    /// Whether the popup is currently shown.
    @State private var autocompleteVisible = false
    /// Monotonic token discarding stale async query results: each trigger bumps it,
    /// and a completed query only applies if its captured token still matches.
    @State private var autocompleteQueryToken = 0

    /// Top padding of the body editor's text container, sized to reserve space
    /// for the title overlay plus an equidistant gap below the divider.
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
        collection: PageSet?,
        set: PageSet? = nil,
        selection: Binding<SidebarSelection>
    ) {
        self.viewModel = viewModel
        self.vault = vault
        self.collection = collection
        self.set = set
        self._selection = selection
        self._titleDraft = State(initialValue: viewModel.page.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            // No inline properties pulldown here — it obstructed the titlebar.
            // FrontmatterInspector surfaces page properties via the pop-out
            // inspector pane when explicitly opened.
            editorZStack
                .overlay(alignment: .bottomTrailing) { statsChevron }

            if statsExpanded {
                Divider()
                PageStatsBar(crumbs: breadcrumbCrumbs, stats: stats)
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

    /// Breadcrumb segments for the stats bar footer. Vault and depth-1
    /// Collection ancestors are tappable; depth-2+ Set segments are plain
    /// (no detail surface). Walks the full Set ancestor chain so pages nested
    /// at arbitrary depth show the complete path.
    private var breadcrumbCrumbs: [FooterCrumb] {
        var crumbs: [FooterCrumb] = [
            FooterCrumb(title: vault.title) { selection = .pageType(vault) }
        ]
        if let c = collection {
            crumbs.append(FooterCrumb(title: c.title) { selection = .collection(c) })
            if let immediateSet = set {
                for ancestor in pageSetManager.setAncestors(from: immediateSet) {
                    crumbs.append(FooterCrumb(title: ancestor.title))
                }
                crumbs.append(FooterCrumb(title: immediateSet.title))
            }
        }
        crumbs.append(FooterCrumb(title: viewModel.page.title))
        return crumbs
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
        .padding(.trailing, PUI.Spacing.xxl)
        // Snug above the bar when open; comfortably inset from the window edge
        // when collapsed.
        .padding(.bottom, statsExpanded ? PUI.Spacing.xs : PUI.Spacing.xl)
        .accessibilityLabel(statsExpanded ? "Hide statistics" : "Show statistics")
    }

    private var editorZStack: some View {
        ZStack(alignment: .topLeading) {
            // Body editor — TextKit-2 native via the in-tree MarkdownPM package.
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
            MarkdownPMEditor(
                text: $viewModel.body,
                pendingInlineReplacement: $pendingInlineReplacement,
                foldedHeadings: $viewModel.foldedHeadings,
                configuration: pommoraEditorConfiguration,
                fontName: "SF Pro Text",
                fontSize: 15,
                documentId: viewModel.page.id,
                onLinkClick: { title in
                    // The hook is sync + passes the link's display TITLE (Pommora
                    // stores links title-only, LD-28). Resolution is async, so
                    // hop a Task: resolve the title → page selection via the index,
                    // then route it into the main detail pane. nil = phantom /
                    // ambiguous / unreadable target → no-op.
                    Task { @MainActor in
                        guard let index = contentManager.indexUpdater?.index else { return }
                        guard let selection = await WikiLinkPageOpener.pageSelection(
                            forTitle: title, index: index, nexusRootURL: contentManager.nexus.rootURL)
                        else { return }
                        mainWindowRouter.requestOpen(to: selection)
                    }
                },
                onCaretRectChange: { rect in
                    // Caret rect arrives in the body NSTextView's view coords (from
                    // `viewRect(forCharacterRange:)`). The editor fills the ZStack, so
                    // this maps to the editor's coordinate space — the popup anchors off
                    // it. Refreshes on scroll too (the package re-emits via
                    // `refreshActiveLinkCaretRect`), so the popup follows `[[ ]]`.
                    caretRect = rect
                },
                onInlineSelectionChange: { state in
                    handleInlineSelectionChange(state)
                },
                onScrollOffsetChange: { newOffset in
                    if abs(scrollOffset - newOffset) > 0.5 {
                        scrollOffset = newOffset
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Caret-anchored autocomplete popup. Origin = bracket x, just below the
            // caret line (`caretRect.maxY`). Anchored in the editor's own coordinate
            // space via `.topLeading` overlay + `.offset`.
            // TODO(visual): the 90pt top safe-area inset + scroll offset can shift
            // the NSTextView→SwiftUI y-mapping by a few points. The popup already
            // lands on the correct line, near the typed brackets.
            .overlay(alignment: .topLeading) {
                if autocompleteVisible {
                    AutoCompleteWindow(
                        candidates: autocompleteCandidates,
                        query: activeInlineSelection?.selection.placeholder ?? "",
                        onSelect: { candidate in commitAutocomplete(candidate) },
                        onCancel: { dismissAutocomplete() }
                    )
                    .fixedSize()
                    .offset(x: caretRect.minX, y: caretRect.maxY)
                }
            }

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
                // Title row. When the per-Nexus `showPageIcon` setting is on and
                // the page has an icon, it renders inline to the LEFT of the
                // title. When the setting is on but no icon is set, hovering the
                // row reveals a faint "Add Icon" affordance on the RIGHT. In every
                // other state nothing leads the title, so it stays flush-left with
                // zero reserved indent.
                // `.firstTextBaseline` sits the inline icon on the title's text
                // baseline (centered alignment floated it slightly high).
                HStack(alignment: .firstTextBaseline, spacing: PUI.Spacing.sm) {
                    if showInlinePageIcon, let icon = pageIcon {
                        Image(systemName: icon)
                            .font(PUI.Typography.Fixed.f26)
                            .foregroundStyle(.primary)
                    }
                    if isRenamingTitle {
                        TextField("Untitled", text: $titleDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .focused($titleFocused)
                            .onSubmit {
                                // Exit rename FIRST so the focus-loss handler
                                // below doesn't double-commit, then hand AppKit
                                // firstResponder to the body editor.
                                isRenamingTitle = false
                                titleFocused = false
                                focusBodyEditor()
                                Task { await commitRename() }
                            }
                            .onExitCommand { cancelTitleRename() }
                    } else {
                        Text(viewModel.page.title.isEmpty ? "Untitled" : viewModel.page.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(viewModel.page.title.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, PUI.Spacing.xxxl)
                .padding(.top, PUI.Spacing.xxxl)
                .padding(.bottom, PUI.Spacing.s14)
                .contextMenu {
                    Button("Rename") { startTitleRename() }
                    if settingsManager.settings.showPageIcon {
                        Button(pageIcon == nil ? "Add Icon" : "Change Icon") {
                            iconPickerOpen = true
                        }
                    }
                }
                .iconPickerPopover(isPresented: $iconPickerOpen, symbol: pageIconBinding)
                .onChange(of: titleFocused) { _, focused in
                    // Click-away voids the edit — commit happens only on Enter.
                    if !focused && isRenamingTitle { cancelTitleRename() }
                }

                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 1)
                    .padding(.horizontal, PUI.Spacing.xxxl)
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
        .onChange(of: iconPickerOpen) { _, isOpen in
            // When the icon picker popover closes, reclaim first responder for
            // the body editor. Otherwise AppKit's popover-dismiss first-
            // responder fallback lands on the sidebar NSSearchField, which
            // reads as the sidebar search "auto-focusing" after an icon edit.
            if !isOpen { focusBodyEditor() }
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
    ///
    /// Instance-level (not `static`) so it can wire the per-Nexus injected
    /// connection resolver into the config's services. Rebuilding the config
    /// VALUE per render is cheap and safe — it references the STABLE injected
    /// resolver instance, so the `MarkdownPMEditor` NSViewRepresentable sees
    /// the same resolver identity across keystrokes and doesn't churn.
    private var pommoraEditorConfiguration: MarkdownPMConfiguration {
        MarkdownEditorConfig.pommora(
            verticalInset: Self.titleAreaHeight,
            pageResolver: connectionResolver
        )
    }

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

    // MARK: - Page icon (header)

    /// The page's icon, normalized to nil when absent or empty.
    private var pageIcon: String? { viewModel.page.frontmatter.icon.nonEmpty }

    /// Inline icon shows only when the per-Nexus setting is on AND an icon is set.
    private var showInlinePageIcon: Bool {
        settingsManager.settings.showPageIcon && pageIcon != nil
    }

    /// Bridges the icon picker to the page's frontmatter: reads the current icon;
    /// on pick/remove, persists via `commitIcon`.
    private var pageIconBinding: Binding<String?> {
        Binding(
            get: { pageIcon },
            set: { newIcon in Task { await commitIcon(newIcon) } }
        )
    }

    /// Enter inline-rename mode for the title (from the header's right-click menu).
    /// Focus is deferred so the TextField is mounted before it's focused.
    private func startTitleRename() {
        titleDraft = viewModel.page.title
        isRenamingTitle = true
        DispatchQueue.main.async { titleFocused = true }
    }

    /// Cancel inline rename (Esc), reverting the draft to the committed title.
    private func cancelTitleRename() {
        titleDraft = viewModel.page.title
        isRenamingTitle = false
        titleFocused = false
    }

    /// The current PageMeta freshly resolved from the manager cache by id — the
    /// set-vs-collection-vs-vault-root branch in one place. Used after a manager
    /// mutation (icon edit / rename) to refresh `viewModel.page` so the next
    /// body save re-serializes current frontmatter, not a stale copy.
    private func currentPageMetaFromCache() -> PageMeta? {
        if let set {
            return contentManager.pages(in: set).first { $0.id == viewModel.page.id }
        } else if let collection {
            return contentManager.pages(inCollection: collection).first { $0.id == viewModel.page.id }
        } else {
            return contentManager.pages(in: vault).first { $0.id == viewModel.page.id }
        }
    }

    /// Persists a new (or removed) page icon, then refreshes the VM's PageMeta
    /// from the manager cache. The refresh is essential: the editor re-serializes
    /// `viewModel.page.frontmatter` verbatim on every body save, so without it the
    /// next keystroke would write back the stale (icon-less) frontmatter and undo
    /// the change.
    private func commitIcon(_ newIcon: String?) async {
        do {
            try await contentManager.updatePageIcon(
                viewModel.page, to: newIcon, vault: vault, collection: collection, set: set)
            if let updated = currentPageMetaFromCache() { viewModel.page = updated }
        } catch {
            viewModel.pendingError = error
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
            if let set, let collection {
                try await contentManager.renamePage(
                    viewModel.page, to: newTitle, in: set, collection: collection, vault: vault
                )
            } else if let collection {
                try await contentManager.renamePage(
                    viewModel.page, to: newTitle, in: collection, vault: vault
                )
            } else {
                try await contentManager.renamePage(
                    viewModel.page, to: newTitle, inVaultRoot: vault
                )
            }
            // Pick up the freshly-renamed PageMeta from the manager cache.
            if let updated = currentPageMetaFromCache() {
                viewModel.page = updated
                titleDraft = updated.title
            }
        } catch {
            viewModel.pendingError = error
            titleDraft = oldTitle
        }
    }

    // MARK: - `[[` autocomplete

    /// Reacts to the editor's inline-selection changes: gates on the Nathan-locked
    /// trigger (a `[[ ]]` token with a non-empty typed placeholder), then
    /// launches a stale-guarded index query and shows the popup when there are
    /// candidates. Anything else dismisses the popup.
    private func handleInlineSelectionChange(_ state: InlineSelectionState?) {
        guard AutoCompleteWiring.shouldShowAutocomplete(for: state), let state else {
            dismissAutocomplete()
            return
        }
        activeInlineSelection = state
        let placeholder = state.selection.placeholder

        // Bump the token; only results from THIS query (matching token + still the
        // current placeholder) are applied — a faster keystroke supersedes a slower
        // in-flight query.
        autocompleteQueryToken += 1
        let token = autocompleteQueryToken
        Task { @MainActor in
            guard let index = contentManager.indexUpdater?.index else { return }
            let refs = (try? await IndexQuery(index).titleCandidates(matching: placeholder)) ?? []
            // Stale-guard: discard if a newer trigger has fired or the placeholder
            // moved on since this query launched.
            guard token == autocompleteQueryToken,
                  activeInlineSelection?.selection.placeholder == placeholder
            else { return }
            let candidates = AutoCompleteWiring.candidates(from: refs)
            autocompleteCandidates = candidates
            autocompleteVisible = !candidates.isEmpty
        }
    }

    /// Commits a chosen candidate: builds the title-only storage fragment (LD-28),
    /// pushes it into the editor (which replaces the token + restores the caret),
    /// then dismisses the popup.
    private func commitAutocomplete(_ candidate: AutoCompleteCandidate) {
        guard let state = activeInlineSelection else { return }
        pendingInlineReplacement = InlineReplacementRequest(
            documentId: viewModel.page.id,
            selection: state.selection,
            storageFragment: AutoCompleteWiring.fragment(title: candidate.title),
            isImageEmbedMode: false
        )
        dismissAutocomplete()
    }

    private func dismissAutocomplete() {
        autocompleteVisible = false
        autocompleteCandidates = []
        activeInlineSelection = nil
    }
}
