import AppKit
import SwiftUI

/// The exact dark-mode value of `.primary` (`NSColor.labelColor`), resolved once
/// into a FIXED color. `SelectableRow`'s title + icon use this rather than semantic
/// `.primary` so they (1) match `.primary` precisely on the live rows and (2) can't
/// flip to black in the native `.onMove` drag-image snapshot, which renders in a
/// light appearance regardless of the (dark) window. Pommora's sidebar is dark-only.
private let sidebarLabelColor: Color = {
    var cg = NSColor.labelColor.cgColor
    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
        cg = NSColor.labelColor.cgColor
    }
    return Color(cgColor: cg)
}()

struct SidebarView: View {
    @Environment(AreaManager.self) private var areaManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageSetManager.self) private var pageSetManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(AgendaTaskManager.self) private var agendaTaskManager
    @Environment(AgendaEventManager.self) private var agendaEventManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SidebarSectionsManager.self) private var sidebarSectionsManager

    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?

    @State private var presentedSheet: SidebarSheet? = nil
    @State private var confirmingDelete: SidebarConfirmation? = nil

    // Drives the AppKit drag/select gesture chain via `List(selection:)`.
    @State private var selectedTag: SelectionTag? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Outside the List so it doesn't touch Section layout (quirk #7).
            SidebarToast()
            List(selection: $selectedTag) {
                // Homepage header — the first row, in its own Section so it
                // scrolls with the list; native selection + chrome (quirk #6/#7).
                Section {
                    NexusHeaderBanner()
                        .tag(SelectionTag.savedKey("homepage"))
                        // Negative leading reclaims the chevron-gutter allowance the
                        // List reserves on every row — the SwiftUI-List analog of
                        // ChevronlessOutlineView's frameOfCell shift (detail table).
                        .listRowInsets(EdgeInsets(top: 1, leading: -8, bottom: 1, trailing: 0))
                        .listRowBackground(
                            SelectionChrome(
                                isSelected: SelectionTag.savedKey("homepage").matches(selection)
                            )
                        )
                }
                ContextsSection(
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                VaultsSection(
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                // User vault sections (PagesV2 P9) — each a SIBLING Section
                // with the IDENTICAL `Section(isExpanded:) { rows } header:`
                // shape as VaultsSection, reusing PageTypeRow unchanged
                // (quirk #6: never mix row shapes inside one Section).
                ForEach(sidebarSectionsManager.config.sections) { userSection in
                    UserVaultSection(
                        section: userSection,
                        selection: $selection,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        presentedSheet: $presentedSheet,
                        confirmingDelete: $confirmingDelete
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedTag) { _, newTag in
                let lookup = SidebarLookupBundle(
                    content: contentManager,
                    pageType: vaultManager,
                    area: areaManager,
                    topic: topicManager,
                    project: projectManager
                )
                guard let newTag else {
                    if selection != .none { selection = .none }
                    return
                }
                guard let resolved = SidebarSelection(tag: newTag, lookup: lookup) else { return }
                // Open-in routing (V8): a page tap consults its vault's
                // `open_in` mode — `.window` renders in the detail pane
                // (selection change), `.compact` opens/focuses a PagePreview
                // card WITHOUT moving the selection. The edit-conflict guard
                // (`.suppressed`) keeps a main-pane page from ever previewing.
                if case .page(let p) = resolved {
                    let routed = PageOpenRouter.routeOpen(
                        p, selection: &selection,
                        content: contentManager, vaultManager: vaultManager,
                        setManager: pageSetManager,
                        openPreview: { openPagePreview($0) })
                    if routed != .detailPane {
                        // Snap the row highlight back to the still-active
                        // main-pane selection (the List already moved it).
                        selectedTag = SelectionTag(selection)
                    }
                } else if selection != resolved {
                    selection = resolved
                }
            }
            .onChange(of: selection) { _, newSelection in
                let derivedTag = SelectionTag(newSelection)
                if derivedTag != selectedTag { selectedTag = derivedTag }
            }
            .onAppear {
                let derivedTag = SelectionTag(selection)
                if derivedTag != selectedTag { selectedTag = derivedTag }
            }
            .background(NSTableSelectionStyleSuppressor())  // Nathan's Note: This is what prevents the double-accent fill and allows for the finder-like quartenary opacity.
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .editIcon(let target): IconPickerSheet(target: target)
            }
        }
        .confirmationDialog(
            confirmingDelete?.dialogTitle ?? "",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { confirmation in
            confirmationButtons(for: confirmation)
        } message: { confirmation in
            Text(confirmation.dialogMessage)
        }
    }

    /// Shared trailing Cancel button for every confirmation branch — dismisses
    /// the dialog without acting.
    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { confirmingDelete = nil }
    }

    @ViewBuilder
    private func confirmationButtons(for confirmation: SidebarConfirmation) -> some View {
        switch confirmation {
        case .deleteArea(let s):
            Button("Delete", role: .destructive) {
                Task {
                    await cascadeUnlinkTier(contextID: s.id, tier: 1)
                    do { try await areaManager.delete(s) } catch { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        case .deleteTopic(let t):
            Button("Delete", role: .destructive) {
                Task {
                    await cascadeUnlinkTier(contextID: t.id, tier: 2)
                    do { try await topicManager.delete(t) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        case .deleteProject(let p):
            Button("Delete", role: .destructive) {
                Task {
                    await cascadeUnlinkTier(contextID: p.id, tier: 3)
                    do { try await projectManager.delete(p) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        case .deleteVault(let v, _):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await vaultManager.deletePageType(v) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        case .deleteCollection(let c):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await vaultManager.deletePageCollection(c) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        case .deleteSet(let s):
            Button("Delete Set Only") {
                Task {
                    do { try await pageSetManager.deletePageSet(s, mode: .setOnly) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Delete Set and Pages", role: .destructive) {
                Task {
                    do { try await pageSetManager.deletePageSet(s, mode: .withPages) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        case .moveSet(let s, let dest, let destVault, let srcVault, _):
            Button("Move", role: .destructive) {
                Task {
                    do {
                        try await pageSetManager.moveSet(
                            s, to: dest, destinationVault: destVault,
                            sourceVault: srcVault, contentManager: contentManager)
                    } catch { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            cancelButton
        }
    }

    /// Removes a Context's ID from every referencing entity's tier array across all
    /// content kinds, BEFORE the Context file is deleted (the unlink queries the
    /// SQLite `context_links` index, so the refs must still resolve at call time).
    /// Best-effort per manager — one failure must not block the others or the delete.
    private func cascadeUnlinkTier(contextID: String, tier: Int) async {
        guard let index = nexusManager.currentIndex else { return }  // degraded mode: skip cascade
        try? await contentManager.unlinkTier(contextID: contextID, tier: tier, index: index)
        try? await agendaTaskManager.unlinkTier(contextID: contextID, tier: tier, index: index)
        try? await agendaEventManager.unlinkTier(contextID: contextID, tier: tier, index: index)
    }
}

// MARK: - Sections

struct VaultsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(SidebarSectionsManager.self) private var sectionsManager

    @State private var expanded: Bool = true
    @State private var isCreating: Bool = false
    @State private var isCreatingSection: Bool = false

    /// The default Vaults section shows only UNGROUPED vaults — those not
    /// claimed by any user section (PagesV2 P9, single-membership).
    private var ungroupedTypes: [PageType] {
        let grouped = sectionsManager.config.groupedVaultIDs
        return vaultManager.types.filter { !grouped.contains($0.id) }
    }

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(ungroupedTypes) { pageType in
                PageTypeRow(
                    pageType: pageType,
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete,
                    nexus: nexusManager.currentNexus ?? Nexus(id: "", rootURL: URL(filePath: "/")),
                    index: nexusManager.currentIndex
                )
                .tag(SelectionTag.pageType(pageType.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    reorderUngrouped(fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            SectionHeader(
                title: settingsManager.settings.labels.sidebarSections.pages,
                onAdd: { createPageType() }
            ) {
                Divider()
                Button("Add Section") { createUserSection() }
                    .disabled(isCreatingSection)
            }
        }
    }

    /// Translates drag offsets from the displayed (ungrouped-only) list back
    /// into `vaultManager.types` offsets before forwarding to the existing
    /// full-array reorder. When no vault is grouped the mapping is the
    /// identity, preserving pre-P9 behavior exactly.
    private func reorderUngrouped(fromOffsets source: IndexSet, toOffset destination: Int) {
        let displayed = ungroupedTypes
        let full = vaultManager.types
        let fullIndices: [Int] = displayed.compactMap { d in
            full.firstIndex(where: { $0.id == d.id })
        }
        guard fullIndices.count == displayed.count else { return }  // stale snapshot — drop
        let translatedSource = IndexSet(
            source.compactMap { $0 < fullIndices.count ? fullIndices[$0] : nil })
        let translatedDestination: Int
        if destination >= displayed.count {
            translatedDestination = fullIndices.last.map { $0 + 1 } ?? full.count
        } else {
            translatedDestination = fullIndices[destination]
        }
        vaultManager.reorderPageTypes(
            fromOffsets: translatedSource, toOffset: translatedDestination)
    }

    private func createPageType() {
        guard !isCreating else { return }
        isCreating = true
        let label = settingsManager.settings.labels.pageType.singular
        let existing = vaultManager.types.map(\.title)
        let title = DefaultTitleResolver.resolve(label: label, existingTitles: existing)
        Task {
            defer { isCreating = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await vaultManager.createPageType(name: title, icon: nil)
                    },
                    onCreate: { newType in
                        editingID = newType.id
                        justCreatedID = newType.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Stub-and-edit "Add Section" trigger (PagesV2 P9). Creates a uniquely
    /// labelled empty user section, then flips its header into inline-rename
    /// mode with the default label pre-selected — the same
    /// `CreateWithInlineEdit` flow every other "New X" uses.
    private func createUserSection() {
        guard !isCreatingSection else { return }
        isCreatingSection = true
        let existing = sectionsManager.config.sections.map(\.label)
        let title = DefaultTitleResolver.resolve(label: "Section", existingTitles: existing)
        Task {
            defer { isCreatingSection = false }
            do {
                _ = try await CreateWithInlineEdit.run(
                    create: {
                        try await sectionsManager.createSection(label: title)
                    },
                    onCreate: { newSection in
                        editingID = newSection.id
                        justCreatedID = newSection.id
                    }
                )
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }
}

// MARK: - UserVaultSection (PagesV2 P9)

/// One user-created sidebar section grouping Vaults — a SIBLING `Section`
/// with the IDENTICAL `Section(isExpanded:) { rows } header:` shape as
/// `VaultsSection`, reusing `PageTypeRow` unchanged (quirk #6: row shapes
/// inside a Section must stay homogeneous; selection chrome stays at the
/// row file level per quirk #7).
///
/// Membership is navigation-only: `section.vaultIDs` resolve to live
/// `PageType`s in section order; dangling IDs (a deleted vault's ID left in
/// the config) skip-render. An EMPTY section renders its header with zero
/// rows — zero rows is trivially homogeneous, and the header must stay
/// visible so a freshly created section can be inline-renamed.
struct UserVaultSection: View {
    let section: SidebarSectionsConfig.Section
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(NexusManager.self) private var nexusManager

    @State private var expanded: Bool = true

    /// `vaultIDs` resolved to live PageTypes in section order. Dangling IDs
    /// are skipped (skip-render policy — the config is not self-healed).
    private var resolvedTypes: [PageType] {
        let types = vaultManager.types
        return section.vaultIDs.compactMap { id in
            types.first(where: { $0.id == id })
        }
    }

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(resolvedTypes) { pageType in
                PageTypeRow(
                    pageType: pageType,
                    selection: $selection,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete,
                    nexus: nexusManager.currentNexus ?? Nexus(id: "", rootURL: URL(filePath: "/")),
                    index: nexusManager.currentIndex
                )
                .tag(SelectionTag.pageType(pageType.id))
            }
        } header: {
            UserSectionHeader(
                section: section,
                editingID: $editingID,
                justCreatedID: $justCreatedID
            )
        }
    }
}

/// Header for a user vault section: secondary-styled label matching
/// `SectionHeader`'s strip, flipping into an inline-rename `TextField` when
/// `editingID == section.id` (mirrors the `RenameableRow` commit/cancel/
/// focus-loss contract, minus the icon slot — headers carry no symbol).
/// Context menu: Rename Section / Delete Section (delete is navigation-only —
/// the section's vaults return to the default Vaults section).
private struct UserSectionHeader: View {
    let section: SidebarSectionsConfig.Section
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @Environment(SidebarSectionsManager.self) private var sectionsManager

    @State private var draft: String = ""
    @State private var isCommitting: Bool = false
    @FocusState private var renameFocused: Bool

    var body: some View {
        if editingID == section.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commit() }
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && !isCommitting && editingID == section.id {
                        cancel()
                    }
                }
                .onAppear {
                    draft = section.label
                    renameFocused = true
                    if justCreatedID == section.id {
                        InlineRenameFocus.selectAllOnNextRunloop()
                    }
                }
        } else {
            HStack(spacing: PUI.Spacing.xs) {
                Text(section.label)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Rename Section") { editingID = section.id }
                Button("Delete Section") { deleteSection() }
            }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != section.label else {
            editingID = nil
            justCreatedID = nil
            return
        }
        isCommitting = true
        Task {
            defer { isCommitting = false }
            do {
                try await sectionsManager.renameSection(id: section.id, to: trimmed)
                editingID = nil
                justCreatedID = nil
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func cancel() {
        editingID = nil
        justCreatedID = nil
    }

    private func deleteSection() {
        Task {
            do {
                try await sectionsManager.deleteSection(id: section.id)
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }
}

// MARK: - SelectableRow

/// Self-contained sidebar row content. Selection chrome is painted at the
/// row-file level via `.listRowBackground(SelectionChrome(...))` so the fill
/// covers the full List row including any DisclosureGroup chevron gutter — not
/// just the label area. `trailing` is an optional ViewBuilder slot for callers
/// that need to render content at the right edge of the row. A `nil` tag marks
/// a non-selectable row (PageSet labels pass nil — their `.set` tag is
/// identity-only and never matches a selection) — same content, never
/// highlighted.
struct SelectableRow<Trailing: View>: View {
    let title: String
    let symbol: String
    let tag: SelectionTag?
    @Binding var selection: SidebarSelection
    let accent: Color?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        symbol: String,
        tag: SelectionTag?,
        selection: Binding<SidebarSelection>,
        accent: Color?,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.symbol = symbol
        self.tag = tag
        self._selection = selection
        self.accent = accent
        self.trailing = trailing
    }

    var isSelected: Bool {
        tag?.matches(selection) ?? false
    }

    var body: some View {
        // Pure content — tap + drag are driven by `List(selection:)` +
        // `.onMove` at the SidebarView level via the row's `.tag(...)`.
        HStack(spacing: PUI.Spacing.md) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isSelected ? Color.accentColor : (accent ?? sidebarLabelColor))
                .frame(width: 16, height: 16, alignment: .center)
            Text(title)
                .foregroundStyle(isSelected ? Color.accentColor : sidebarLabelColor)
                .brightness(isSelected ? 0.10 : 0)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, PUI.Spacing.xs)
        .padding(.trailing, 0)
        .padding(.vertical, PUI.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
    }
}

struct SelectionChrome: View {
    enum Style {
        case flat
        case disclosure

        var insets: EdgeInsets {
            switch self {
            case .flat: return EdgeInsets(top: PUI.Spacing.xxs, leading: 11, bottom: PUI.Spacing.xxs, trailing: 11)
            case .disclosure: return EdgeInsets(top: PUI.Spacing.xxs, leading: 0, bottom: PUI.Spacing.xxs, trailing: 11)
            }
        }
    }

    let isSelected: Bool
    var style: Style = .flat

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: PUI.Radius.card, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
                .padding(style.insets)
        } else {
            Color.clear
        }
    }
}

// MARK: - SectionHeader

/// Section header strip used by Areas / Topics / Vaults: secondary-styled title,
/// trailing "+" button that fades in on hover (matching the disclosure-chevron's
/// hover affordance), and a section-wide right-click context menu offering the
/// same action regardless of hover state. `extraMenu` is an optional ViewBuilder
/// slot appended to that context menu (the Vaults header uses it for
/// "Add Section", PagesV2 P9); it defaults to empty so the other call sites
/// stay unchanged.
private struct SectionHeader<ExtraMenu: View>: View {
    let title: String
    let onAdd: () -> Void
    @ViewBuilder let extraMenu: () -> ExtraMenu

    @State private var hovered: Bool = false

    init(
        title: String,
        onAdd: @escaping () -> Void,
        @ViewBuilder extraMenu: @escaping () -> ExtraMenu = { EmptyView() }
    ) {
        self.title = title
        self.onAdd = onAdd
        self.extraMenu = extraMenu
    }

    var body: some View {
        HStack(spacing: PUI.Spacing.xs) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New")
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .animation(.easeInOut(duration: 0.12), value: hovered)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("New") { onAdd() }
            extraMenu()
        }
    }
}
