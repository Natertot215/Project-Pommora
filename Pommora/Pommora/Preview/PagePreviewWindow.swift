import AppKit
import MarkdownPM
import SwiftUI

// MARK: - Metrics

/// Tunable geometry for the PagePreview window — every value here is a
/// deliberate design constant; adjust on sight, never inline.
enum PreviewWindowMetrics {
    /// Default window size with the inspector OPEN (its default state).
    /// Width = minBodySize.width (420) + inspector (210) + body headroom
    /// (210) — agreeing with the window's effective width floor so the
    /// inspector toggle moves the frame by EXACTLY the pane width from the
    /// very first click (a default below the floor would clamp once).
    static let defaultSize = CGSize(width: 840, height: 540)
    /// Minimum size of the BODY column (the window's min width grows by the
    /// inspector width while the inspector is presented).
    static let minBodySize = CGSize(width: 420, height: 360)
    /// Fixed inspector pane width (Figma delta: 685 − 475).
    static let inspectorWidth: CGFloat = 210
    /// Horizontal rail shared by the header content, both hairline insets,
    /// and the footer — separator ends align with the capsules' bounds
    /// (uniform-distance dividers).
    static let railPadding: CGFloat = PUI.Spacing.xl
    /// Header vertical rhythm: padding(top→title) == padding(title→separator).
    /// Title-bar height = capsule 26 + 2×10 = 46pt — the standard unified-
    /// toolbar height, which also lands the header hairline on the
    /// inspector's first context-row divider (10pt card inset + 36pt row).
    static let headerVPad: CGFloat = PUI.Spacing.lg
    /// Editor type size — reduced from the main editor's 15 so the body
    /// reads as a PREVIEW of the document, not a 1:1 editor.
    static let bodyFontSize: CGFloat = 13
    /// Vertical text inset above/below the body so the reduced type
    /// doesn't sit squished against the hairlines.
    static let bodyVerticalInset: CGFloat = PUI.Spacing.xl
}

// MARK: - PagePreviewWindowRoot

/// Root of the `WindowGroup(id: "page-preview", for: PageRef.self)` scene.
/// Bootstraps the per-Nexus environment from `AppGlobals.current` (published
/// by `NexusEnvironment` exactly for standalone scenes) and self-dismisses
/// when there's nothing to show (no open Nexus / valueless open).
struct PagePreviewWindowRoot: View {
    let ref: PageRef?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let ref, let env = AppGlobals.current {
            PagePreviewContent(ref: ref)
                .injectNexusEnvironment(env)
        } else {
            Color.clear
                .frame(width: 200, height: 120)
                .task { dismiss() }
        }
    }
}

// MARK: - PagePreviewContent

/// One Page previewed in a real window. The window is standard in every
/// material respect — `windowBackground`, system shadow, edge resize, native
/// titlebar-strip drag — restricted by `PreviewWindowConfigurator` so it
/// never reads as its own app window.
///
/// Chrome: title bar = ✕ glass capsule · page icon + inline-editable title
/// (15pt semibold, the native title voice) · inspector glass capsule;
/// uniform-inset hairlines above the body and above the footer; footer =
/// breadcrumb + lock (+ Open revealed by unlock). Body = the page's
/// `MarkdownPMEditor`, lock-gated on the same `PageEditorViewModel` save
/// path as the main editor.
///
/// "Grow" gestures promote instead of expanding: Ctrl-Cmd-F and a title-bar
/// double-click route to Open-in-main-pane; native fullscreen and zoom are
/// disabled outright.
struct PagePreviewContent: View {
    let ref: PageRef

    @Environment(PageContentManager.self) private var contentManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(MainWindowRouter.self) private var router
    @Environment(ContextDisplayResolver.self) private var contextResolver
    @Environment(\.connectionResolver) private var connectionResolver
    @Environment(\.dismiss) private var dismiss

    /// Same VM + saver the main `PageEditorView` uses — unlocked edits flow
    /// through the identical debounced `ContentManager.updatePage` path.
    @State private var viewModel: PageEditorViewModel?
    @State private var vault: PageType?
    @State private var collection: PageCollection?
    @State private var loadFailed = false

    /// Lock-gated editing: opens locked (read-only); the footer Lock glyph
    /// and the context menu toggle it.
    @State private var isLocked = true
    /// Inspector pane — defaults OPEN; toggling widens/shrinks the window
    /// so the body column never squeezes.
    @State private var inspectorShown = true
    /// Live NSWindow handle surfaced by the configurator — drives the
    /// widen/shrink frame animation.
    @State private var window: NSWindow?

    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var iconPickerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, PreviewWindowMetrics.railPadding)
                .padding(.vertical, PreviewWindowMetrics.headerVPad)
            hairline
            bodyEditor
            hairline
            footer
                .padding(.horizontal, PreviewWindowMetrics.railPadding)
                .padding(.vertical, PUI.Spacing.md)
        }
        .frame(
            minWidth: PreviewWindowMetrics.minBodySize.width,
            minHeight: PreviewWindowMetrics.minBodySize.height
        )
        // The hidden title bar still reserves a top safe-area strip — without
        // this the header floats ~28pt below the window's top edge. The
        // header IS the title bar; it owns the top edge.
        .ignoresSafeArea(.container, edges: .top)
        .inspector(isPresented: $inspectorShown) {
            inspectorContent
                .inspectorColumnWidth(PreviewWindowMetrics.inspectorWidth)
                .interactiveDismissDisabled()
        }
        .background(PreviewWindowConfigurator(window: $window))
        // A preview can never minimize to the Dock, zoom, or become its own
        // fullscreen Space.
        .windowMinimizeBehavior(.disabled)
        .windowFullScreenBehavior(.disabled)
        .windowResizeAnchor(.topLeading)
        // The "make this big" muscle-memory shortcut promotes to the main
        // pane instead of fullscreening.
        .background {
            Button("", action: openInMainPane)
                .keyboardShortcut("f", modifiers: [.control, .command])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task(id: ref) { await load() }
        .onDisappear {
            // Flush any pending debounced save before the window goes away
            // (close, promotion, Nexus switch, parent close).
            if let vm = viewModel {
                AppGlobals.unregister(vm)
                Task { await vm.close() }
            }
        }
    }

    /// Uniform-distance divider: hairline inset to the rail at BOTH ends,
    /// identical above the body and above the footer.
    private var hairline: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .padding(.horizontal, PreviewWindowMetrics.railPadding)
    }

    // MARK: - Header (the title bar)

    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            WindowCapsuleButton(symbol: "xmark", help: "Close Preview") { closeWindow() }

            HStack(spacing: PUI.Spacing.sm) {
                iconAffordance
                TextField("Untitled", text: $titleDraft)
                    .textFieldStyle(.plain)
                    // Native title-bar voice, sized for this window's
                    // proportions. Still inline-editable.
                    .font(.system(size: 15, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit { Task { await commitRename() } }
                    .onChange(of: titleFocused) { wasFocused, isFocused in
                        // Commit on click-out (blur), not just Enter.
                        if wasFocused && !isFocused { Task { await commitRename() } }
                    }
            }
            .contextMenu { menuCommands }

            Spacer(minLength: PUI.Spacing.md)

            WindowCapsuleButton(symbol: "sidebar.trailing", help: "Toggle Inspector") {
                toggleInspector()
            }
        }
        .contentShape(Rectangle())
        // Title-bar double-click "zoom" → promote. Native zoom is disabled,
        // so this is the only double-click behavior up here.
        .onTapGesture(count: 2) { openInMainPane() }
    }

    /// Page icon (or the default page glyph) — tap opens the existing icon
    /// selector; picks persist via `updatePageIcon` like the main editor.
    private var iconAffordance: some View {
        Button {
            iconPickerOpen = true
        } label: {
            // Proxy-icon scale — the small document icon beside a native
            // window title, tracking the 15pt title.
            Image(systemName: currentIcon ?? "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(currentIcon == nil ? .tertiary : .primary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change page icon")
        .iconPickerPopover(isPresented: $iconPickerOpen, symbol: iconBinding)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyEditor: some View {
        Group {
            if let vm = viewModel {
                @Bindable var vm = vm
                MarkdownPMEditor(
                    text: $vm.body,
                    configuration: editorConfiguration,
                    fontName: "SF Pro Text",
                    fontSize: PreviewWindowMetrics.bodyFontSize,
                    documentId: vm.page.id,
                    isEditable: !isLocked
                )
                .id(vm.page.id)
            } else if loadFailed {
                ContextDetailPlaceholder(
                    title: "Unavailable",
                    icon: "exclamationmark.triangle",
                    accent: nil,
                    supportingLine: "Couldn't load this Page from disk."
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Right-click on the body area: the NSTextView would otherwise consume
        // the click and show its formatting menu; the catcher claims only
        // right-mouse events, so editing/selection/scroll pass through.
        .secondaryClickMenu(bodyMenuItems)
    }

    /// Pommora's shared editor config tuned for the preview surface: the
    /// horizontal text inset is the chrome RAIL — body text sits flush with
    /// the hairlines' insets, never double-indented — while a small vertical
    /// inset keeps the reduced type from squishing against the dividers.
    private var editorConfiguration: MarkdownPMConfiguration {
        MarkdownEditorConfig.pommora(
            verticalInset: PreviewWindowMetrics.bodyVerticalInset,
            horizontalInset: PreviewWindowMetrics.railPadding,
            pageResolver: connectionResolver)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(breadcrumb)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: PUI.Spacing.md)
            // Unlocking REVEALS the Open affordance; locked → only the
            // lock shows.
            if !isLocked {
                Button {
                    openInMainPane()
                } label: {
                    Text("Open")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in the main pane")
                .transition(.opacity)
            }
            Button {
                toggleLock()
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isLocked ? "Unlock for editing" : "Lock (read-only)")
            .accessibilityLabel(isLocked ? "Unlock" : "Lock")
        }
        .animation(.smooth(duration: 0.2), value: isLocked)
    }

    /// Non-navigable context path ("Vault › Collection").
    private var breadcrumb: String {
        [vault?.title, collection?.title]
            .compactMap { $0 }
            .joined(separator: " › ")
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let vm = viewModel, let vault = liveVault {
            // The REAL pages inspector, mounted as-is — parity with the
            // main window by construction, not imitation. Same grouped Form,
            // same editors, same Add Property affordance, same debounced
            // save path (compact typographic scale).
            FrontmatterInspector(
                page: vm.page,
                vault: vault,
                index: contentManager.indexUpdater?.index,
                relationDisplay: contextResolver,
                onSave: { updated in
                    Task {
                        try? await contentManager.updatePageFrontmatter(
                            vm.page, frontmatter: updated, vault: vault, collection: collection)
                        if let refreshed = currentMeta() { vm.page = refreshed }
                    }
                },
                compact: true
            )
            .id(vm.page.id)
            // No top nudge: the cards sit flush at the Form's stock inset,
            // uniform with the side edges.
        } else {
            Color.clear
        }
    }

    /// The vault resolved LIVE from the manager (not the load()-time
    /// snapshot) so schema changes — e.g. a property added through the
    /// inspector's affordance — re-render this window's inspector
    /// immediately.
    private var liveVault: PageType? {
        guard let vault else { return nil }
        return vaultManager.types.first { $0.id == vault.id } ?? vault
    }

    // MARK: - Context-menu commands (title area + body area)

    @ViewBuilder
    private var menuCommands: some View {
        Button(isLocked ? "Unlock" : "Lock") { toggleLock() }
        Button("Open Page") { openInMainPane() }
    }

    private var bodyMenuItems: [SecondaryClickMenu.Item] {
        [
            SecondaryClickMenu.Item(title: isLocked ? "Unlock" : "Lock") { toggleLock() },
            SecondaryClickMenu.Item(title: "Open Page") { openInMainPane() },
        ]
    }

    // MARK: - Actions

    private func toggleLock() {
        isLocked.toggle()
        // Re-locking flushes any pending debounced edit immediately.
        if isLocked, let vm = viewModel {
            Task { await vm.flushNow() }
        }
    }

    /// Inspector toggle widens/shrinks the window by the pane width so the
    /// body column keeps its size (decision #8). The frame animates via the
    /// window server; growth extends from the top-leading anchor.
    private func toggleInspector() {
        // The pane mounts/unmounts INSTANTLY (animation suppressed) so the
        // window's min-width constraint updates atomically — otherwise the
        // animated collapse keeps the old minimum alive and the frame change
        // clamps mid-flight, drifting the width on every toggle. The window
        // frame animation is the only visible motion.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { inspectorShown.toggle() }
        guard let window else { return }
        var frame = window.frame
        frame.size.width += inspectorShown
            ? PreviewWindowMetrics.inspectorWidth
            : -PreviewWindowMetrics.inspectorWidth
        window.setFrame(frame, display: true, animate: true)
    }

    /// "Open Page" promotion: flush the debounced edit BEFORE routing (the
    /// main-pane editor reads the body from disk on selection change), then
    /// route to the main pane and ALWAYS close the preview — the dual-editor
    /// state stays unreachable.
    private func openInMainPane() {
        guard let vm = viewModel else { return }
        Task {
            await vm.flushNow()
            router.requestOpen(to: .page(vm.page))
            dismiss()
        }
    }

    private func closeWindow() {
        dismiss()
    }

    // MARK: - Data load + commits

    /// Resolve the ref → live page/vault/collection, lazily loading the
    /// container's page cache first when needed (a preview can open before
    /// the sidebar/detail ever browsed that container), then build the editor
    /// VM on the same saver path as `PageEditorHost`.
    private func load() async {
        // Defensive: a re-run must not orphan a previously registered VM in
        // the lifecycle-flush registry.
        if let old = viewModel {
            AppGlobals.unregister(old)
            viewModel = nil
        }
        if ref.resolve(vaultManager: vaultManager, contentManager: contentManager) == nil {
            await loadContainer()
        }
        guard
            let resolved = ref.resolve(
                vaultManager: vaultManager, contentManager: contentManager),
            let pageFile = try? PageFile.loadLenient(
                from: resolved.page.url, nexusRoot: contentManager.nexus.rootURL)
        else {
            viewModel = nil
            vault = nil
            collection = nil
            loadFailed = true
            return
        }

        let saver = ContentManagerPageSaver(
            contentManager: contentManager,
            vault: resolved.vault,
            collection: resolved.collection
        )
        let vm = PageEditorViewModel(page: resolved.page, body: pageFile.body, saver: saver)
        viewModel = vm
        vault = resolved.vault
        collection = resolved.collection
        titleDraft = resolved.page.title
        loadFailed = false
        // Lifecycle-flush registry: pending debounced saves survive app
        // background/quit, same as the main editor.
        AppGlobals.register(vm)
    }

    private func loadContainer() async {
        guard let v = vaultManager.types.first(where: { $0.id == ref.vaultID }) else { return }
        if let cid = ref.collectionID,
            let c = vaultManager.pageCollections(in: v).first(where: { $0.id == cid })
        {
            await contentManager.loadAll(for: c)
        } else {
            await contentManager.loadAll(for: v)
        }
    }

    private var currentIcon: String? {
        viewModel?.page.frontmatter.icon.nonEmpty
    }

    private var iconBinding: Binding<String?> {
        Binding(
            get: { currentIcon },
            set: { newIcon in Task { await commitIcon(newIcon) } }
        )
    }

    /// Freshly re-resolve the PageMeta from the manager cache after a
    /// mutation (rename / icon / frontmatter) so the VM re-serializes current
    /// frontmatter on the next body save, not a stale copy.
    private func currentMeta() -> PageMeta? {
        guard let vm = viewModel, let vault else { return nil }
        if let collection {
            return contentManager.pages(in: collection).first { $0.id == vm.page.id }
        }
        return contentManager.pages(in: vault).first { $0.id == vm.page.id }
    }

    private func commitIcon(_ newIcon: String?) async {
        guard let vm = viewModel, let vault else { return }
        try? await contentManager.updatePageIcon(
            vm.page, to: newIcon, vault: vault, collection: collection)
        if let updated = currentMeta() { vm.page = updated }
    }

    /// Filename = title: committing the title TextField renames the on-disk
    /// `.md` via the same manager path as the main editor. Idempotent (guards
    /// unchanged/empty input) so Enter + blur can both fire.
    private func commitRename() async {
        guard let vm = viewModel, let vault else { return }
        let oldTitle = vm.page.title
        let newTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else {
            titleDraft = oldTitle
            return
        }
        guard newTitle != oldTitle else { return }
        do {
            if let collection {
                try await contentManager.renamePage(vm.page, to: newTitle, in: collection, vault: vault)
            } else {
                try await contentManager.renamePage(vm.page, to: newTitle, inVaultRoot: vault)
            }
            if let updated = currentMeta() {
                vm.page = updated
                titleDraft = updated.title
            }
        } catch {
            // pendingError set by manager; toast surfaces. Revert the draft.
            titleDraft = oldTitle
        }
    }
}
