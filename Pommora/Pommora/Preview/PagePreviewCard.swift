import AppKit
import MarkdownPM
import SwiftUI

// MARK: - PreviewOverlayHost

/// The overlay layer mounted by `ContentView` above the detail content:
/// renders one `PagePreviewCard` per open `PreviewStack` entry, stacked by
/// each card's `z`. Empty regions pass hits through to the content beneath
/// (only the cards themselves are hit-testable).
struct PreviewOverlayHost: View {
    @Environment(PreviewStack.self) private var previewStack

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(previewStack.cards) { card in
                    PagePreviewCard(card: card, bounds: proxy.size)
                        .zIndex(card.z)
                }
            }
        }
    }
}

// MARK: - PagePreviewCard

/// An in-window draggable Liquid Glass card previewing one Page (V8 primitive
/// — no scene, no panel; lives on `PreviewOverlayHost` inside the main window).
///
/// Chrome per the Figma capture: header = close capsule + inline-editable
/// icon/title (`.title3`) + inspector-toggle capsule, over a hairline separator
/// inset to the capsules' horizontal rail; body = the page's `MarkdownPMEditor`
/// slightly inset, lock-gated (opens locked/read-only; unlocking makes it
/// fully editable + live-saving through the same `PageEditorViewModel` save
/// path the main editor uses); footer = non-navigable breadcrumb (bottom-left)
/// + the Lock toggle (bottom-right). Right-clicking the body or title shows
/// "Lock/Unlock" + "Open Page" (promotion routes through `MainWindowRouter`
/// and always removes the card — the V8 edit-conflict rule's second half).
///
/// Drag-vs-editor: the card's `DragGesture` sits on the SwiftUI chrome; the
/// body editor is an AppKit `NSTextView`, which consumes mouse events over its
/// own area, so text selection never fights the card drag — no explicit
/// gesture-priority arbitration is needed.
struct PagePreviewCard: View {
    let card: PreviewCard
    /// Overlay-host size; drag + resize clamp the card inside it.
    let bounds: CGSize

    @Environment(PreviewStack.self) private var previewStack
    @Environment(PageContentManager.self) private var contentManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(MainWindowRouter.self) private var router
    @Environment(ContextDisplayResolver.self) private var contextResolver
    @Environment(\.connectionResolver) private var connectionResolver

    /// Same VM + saver the main `PageEditorView` uses — unlocked edits flow
    /// through the identical debounced `ContentManager.updatePage` path.
    @State private var viewModel: PageEditorViewModel?
    @State private var vault: PageType?
    @State private var collection: PageCollection?
    @State private var loadFailed = false

    /// Lock-gated editing: the preview opens locked (read-only); the footer
    /// Lock glyph and the context menu toggle it.
    @State private var isLocked = true
    /// Inspector pane toggle — independent of the lock; widens the card.
    @State private var inspectorShown = false

    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var iconPickerOpen = false

    /// Origin captured on drag start; nil while not dragging.
    @State private var dragStartPosition: CGPoint?
    /// Size captured on resize-grip drag start; nil while not resizing.
    @State private var resizeStartSize: CGSize?

    /// Width of the toggled inspector pane (widens the card beyond `card.size`).
    private static let inspectorWidth: CGFloat = 280
    /// Horizontal rail shared by the header content, the separator inset, and
    /// the footer — the separator stops at the capsules' horizontal bounds.
    private static let railPadding: CGFloat = PUI.Spacing.xl
    /// Header vertical rhythm: padding(top→title) == padding(title→separator).
    private static let headerVPad: CGFloat = PUI.Spacing.xl

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
                .frame(width: card.size.width)
            if inspectorShown {
                Divider()
                inspectorColumn
                    .frame(width: Self.inspectorWidth)
            }
        }
        .frame(height: card.size.height)
        .glassEffect(
            in: RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous))
        .shadow(radius: 16, y: 6)
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .gesture(cardDrag)
        .simultaneousGesture(
            TapGesture().onEnded { previewStack.bringToFront(card) }
        )
        .offset(x: clampedPosition.x, y: clampedPosition.y)
        .task(id: card.ref) { await load() }
        .onDisappear {
            // Flush any pending debounced save before the card goes away
            // (close, promotion, Nexus switch).
            if let vm = viewModel {
                AppGlobals.unregister(vm)
                Task { await vm.close() }
            }
        }
    }

    // MARK: - Main column (header / separator / body / footer)

    private var mainColumn: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Self.railPadding)
                .padding(.vertical, Self.headerVPad)
            // Hairline separator inset to the capsules' horizontal rail —
            // NOT full-bleed; a small gap sits at each end.
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .padding(.horizontal, Self.railPadding)
            bodyEditor
            footer
                .padding(.horizontal, Self.railPadding)
                .padding(.vertical, PUI.Spacing.md)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: PUI.Spacing.md) {
            capsuleControl("xmark", help: "Close Preview") { closeCard() }

            HStack(spacing: PUI.Spacing.sm) {
                iconAffordance
                TextField("Untitled", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .focused($titleFocused)
                    .onSubmit { Task { await commitRename() } }
                    .onChange(of: titleFocused) { wasFocused, isFocused in
                        // Commit on click-out (blur), not just Enter.
                        if wasFocused && !isFocused { Task { await commitRename() } }
                    }
            }
            .contextMenu { menuCommands }

            Spacer(minLength: PUI.Spacing.md)

            capsuleControl("sidebar.trailing", help: "Toggle Inspector") {
                withAnimation(.smooth(duration: 0.25)) { inspectorShown.toggle() }
            }
        }
    }

    /// Small capsule chrome control (close / inspector toggle). Quinary fill —
    /// no nested `.glassEffect` (glass can't sample other glass; the card's
    /// shell is the one glass surface).
    private func capsuleControl(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 19)
                .background(Capsule().fill(PUI.Fill.field))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Page icon (or the default page glyph) — tap opens the existing icon
    /// selector; picks persist via `updatePageIcon` like the main editor.
    private var iconAffordance: some View {
        Button {
            iconPickerOpen = true
        } label: {
            Image(systemName: currentIcon ?? "doc.text")
                .font(.title3)
                .foregroundStyle(currentIcon == nil ? .tertiary : .primary)
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
                    fontSize: 15,
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
        // "Slightly inset" body — the editor reads as a reduced preview.
        .padding(.horizontal, PUI.Spacing.md)
        .padding(.top, PUI.Spacing.sm)
        // Right-click on the body area: the NSTextView would otherwise consume
        // the click and show its formatting menu; the catcher claims only
        // right-mouse events, so editing/selection/scroll pass through.
        .secondaryClickMenu(bodyMenuItems)
    }

    /// Pommora's shared editor config with no title-overlay inset (the card
    /// header carries the title) and the live `[[ ]]` connection resolver.
    private var editorConfiguration: MarkdownPMConfiguration {
        MarkdownEditorConfig.pommora(verticalInset: 0, pageResolver: connectionResolver)
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
    }

    /// Non-navigable context path ("Vault › Collection").
    private var breadcrumb: String {
        [vault?.title, collection?.title]
            .compactMap { $0 }
            .joined(separator: " › ")
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorColumn: some View {
        if let vm = viewModel, let vault {
            // FrontmatterInspector reused verbatim — same debounced-save VM +
            // per-type property rows as the main window's inspector pane.
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
                }
            )
            .id(vm.page.id)
        } else {
            Color.clear
        }
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

    /// "Open Page" promotion: route to the main detail pane and ALWAYS remove
    /// the card (V8 — the dual-editor state is unreachable).
    private func openInMainPane() {
        guard let vm = viewModel else { return }
        router.requestOpen(to: .page(vm.page))
        previewStack.close(card)
    }

    private func closeCard() {
        previewStack.close(card)
    }

    // MARK: - Drag + resize

    /// Card position clamped to the host bounds at render time (covers window
    /// shrink after placement, not just live drags).
    private var clampedPosition: CGPoint {
        clamp(card.position)
    }

    private var totalWidth: CGFloat {
        card.size.width + (inspectorShown ? Self.inspectorWidth + 1 : 0)
    }

    private func clamp(_ origin: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, origin.x), max(0, bounds.width - totalWidth)),
            y: min(max(0, origin.y), max(0, bounds.height - card.size.height))
        )
    }

    /// Drags the card by its chrome/background. The AppKit editor consumes
    /// events over its own area, so this never fires mid-text-selection.
    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartPosition == nil {
                    dragStartPosition = card.position
                    previewStack.bringToFront(card)
                }
                guard let start = dragStartPosition else { return }
                card.position = clamp(
                    CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    ))
            }
            .onEnded { _ in dragStartPosition = nil }
    }

    /// Bottom-right resize grip: two diagonal hairlines (the classic macOS
    /// grip), hit area larger than the glyph. Min size = the collapsed 475².
    private var resizeGrip: some View {
        GripGlyph()
            .stroke(.tertiary, lineWidth: 1)
            .frame(width: 10, height: 10)
            .padding(PUI.Spacing.sm)
            .contentShape(Rectangle())
            .gesture(resizeDrag)
            .accessibilityLabel("Resize")
    }

    private var resizeDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeStartSize == nil {
                    resizeStartSize = card.size
                    previewStack.bringToFront(card)
                }
                guard let start = resizeStartSize else { return }
                let inspectorExtra = inspectorShown ? Self.inspectorWidth + 1 : 0
                let maxWidth = max(
                    PreviewStack.minCardSize.width,
                    bounds.width - card.position.x - inspectorExtra)
                let maxHeight = max(
                    PreviewStack.minCardSize.height,
                    bounds.height - card.position.y)
                card.size = CGSize(
                    width: min(
                        max(PreviewStack.minCardSize.width, start.width + value.translation.width),
                        maxWidth),
                    height: min(
                        max(PreviewStack.minCardSize.height, start.height + value.translation.height),
                        maxHeight)
                )
            }
            .onEnded { _ in resizeStartSize = nil }
    }

    // MARK: - Data load + commits

    /// Resolve the ref → live page/vault/collection, lazily loading the
    /// container's page cache first when needed (a card can open before the
    /// sidebar/detail ever browsed that container — e.g. the Component
    /// Library launcher), then build the editor VM on the same saver path as
    /// `PageEditorHost`.
    private func load() async {
        if card.ref.resolve(vaultManager: vaultManager, contentManager: contentManager) == nil {
            await loadContainer()
        }
        guard
            let resolved = card.ref.resolve(
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
        guard let v = vaultManager.types.first(where: { $0.id == card.ref.vaultID }) else { return }
        if let cid = card.ref.collectionID,
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

    /// Filename = title: committing the header TextField renames the on-disk
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

// MARK: - GripGlyph

/// Two short diagonal hairlines — the classic bottom-right resize affordance.
private struct GripGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
