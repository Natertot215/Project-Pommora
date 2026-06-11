import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AreaManager.self) private var areaManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(AgendaTaskManager.self) private var agendaTaskManager
    @Environment(AgendaEventManager.self) private var agendaEventManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow
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
            // Outside the List so it doesn't touch Section layout (quirk #9).
            SidebarToast()
            List(selection: $selectedTag) {
                SavedSection(selection: $selection)
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
                // (quirk #8: never mix row shapes inside one Section).
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
                        openPreview: { openPagePreview($0, using: openWindow) })
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
            case .editColor(let s): ColorPickerSheet(area: s)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { confirmation in
            confirmationButtons(for: confirmation)
        } message: { confirmation in
            Text(confirmationMessage(for: confirmation))
        }
    }

    private var confirmationTitle: String {
        switch confirmingDelete {
        case .deleteArea(let s)?: return "Delete Area \"\(s.title)\"?"
        case .deleteTopic(let t)?: return "Delete Topic \"\(t.title)\"?"
        case .deleteProject(let p)?: return "Delete Project \"\(p.title)\"?"
        case .deleteVault(let v, _)?: return "Delete Vault \"\(v.title)\"?"
        case .deleteCollection(let c)?: return "Delete Collection \"\(c.title)\"?"
        case nil: return ""
        }
    }

    private func confirmationMessage(for confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .deleteArea: return "This action cannot be undone."
        case .deleteTopic: return "This action cannot be undone."
        case .deleteProject: return "This action cannot be undone."
        case .deleteVault(_, let cols): return "Contains \(cols) Collection(s). All contents will be deleted."
        case .deleteCollection: return "All Pages inside will be deleted."
        }
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
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteTopic(let t):
            Button("Delete", role: .destructive) {
                Task {
                    await cascadeUnlinkTier(contextID: t.id, tier: 2)
                    do { try await topicManager.deleteTopic(t) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteProject(let p):
            Button("Delete", role: .destructive) {
                Task {
                    await cascadeUnlinkTier(contextID: p.id, tier: 3)
                    do { try await projectManager.delete(p) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteVault(let v, _):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await vaultManager.deletePageType(v) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteCollection(let c):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await vaultManager.deletePageCollection(c) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
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

// MARK: - CalendarPinViewModel

/// Extracted view-model for the Calendar pin row context menu.
/// Holds mutable creation-result state so tests can verify callbacks
/// without constructing SwiftUI views (J.5/J.11/K.1 pattern).
@MainActor
@Observable
final class CalendarPinViewModel {
    var lastCreatedTask: AgendaTask?
    var lastCreatedEvent: AgendaEvent?
    var pendingError: (any Error)?

    func createTask(using manager: AgendaTaskManager) async {
        let now = Date()
        let task = AgendaTask(
            id: ULID.generate(),
            title: "New Task",
            icon: nil,
            description: "",
            dueAt: nil,
            dueFloating: false,
            dueAllDay: false,
            startAt: nil,
            completed: false,
            completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: now,
            modifiedAt: now,
            properties: [:]
        )
        do {
            try await manager.createTask(task)
            lastCreatedTask = task
        } catch {
            pendingError = error
        }
    }

    func createEvent(using manager: AgendaEventManager) async {
        let now = Date()
        let event = AgendaEvent(
            id: ULID.generate(),
            title: "New Event",
            icon: nil,
            description: "",
            startAt: now,
            endAt: now.addingTimeInterval(3600),
            allDay: false,
            location: nil,
            recurrence: nil,
            alarmOffsets: [],
            alarmAbsolute: [],
            calendarID: nil,
            eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: now,
            modifiedAt: now,
            properties: [:]
        )
        do {
            try await manager.createEvent(event)
            lastCreatedEvent = event
        } catch {
            pendingError = error
        }
    }
}

// MARK: - SavedSection

struct SavedSection: View {
    @Binding var selection: SidebarSelection
    @Environment(SavedConfigManager.self) private var savedConfigManager
    @Environment(AgendaTaskManager.self) private var agendaTaskManager
    @Environment(AgendaEventManager.self) private var agendaEventManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var calendarPinVM: CalendarPinViewModel = CalendarPinViewModel()

    var body: some View {
        Section {
            ForEach(savedConfigManager.config.items) { item in
                calendarAwareRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func calendarAwareRow(for item: SavedConfig.Item) -> some View {
        let row = SelectableRow(
            title: item.label,
            symbol: iconFor(item.key),
            tag: SelectionTag.savedKey(item.key),
            selection: $selection,
            accent: nil
        )
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.savedKey(item.key).matches(selection)
            )
        )
        .tag(SelectionTag.savedKey(item.key))

        if item.key == "calendar" {
            row.contextMenu {
                let taskLabel = settingsManager.settings.labels.agendaTask.singular
                let eventLabel = settingsManager.settings.labels.agendaEvent.singular
                Button("New \(taskLabel)") {
                    Task { await calendarPinVM.createTask(using: agendaTaskManager) }
                }
                Button("New \(eventLabel)") {
                    Task { await calendarPinVM.createEvent(using: agendaEventManager) }
                }
            }
        } else {
            row
        }
    }

    private func iconFor(_ key: String) -> String {
        switch key {
        case "homepage": return "house"
        case "calendar": return "calendar"
        case "recents": return "clock"
        default: return "questionmark.square"
        }
    }
}

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
/// `VaultsSection`, reusing `PageTypeRow` unchanged (quirk #8: row shapes
/// inside a Section must stay homogeneous; selection chrome stays at the
/// row file level per quirk #9).
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
                        // Same AppKit responder hop as RenameableRow: select
                        // the whole default label so the first keystroke
                        // replaces it.
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.firstResponder?.tryToPerform(
                                #selector(NSText.selectAll(_:)), with: nil
                            )
                        }
                    }
                }
        } else {
            HStack(spacing: 4) {
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

// MARK: - SelectableRow (updated to use SelectionTag)

/// Self-contained sidebar row content. Selection chrome is painted at the
/// row-file level via `.listRowBackground(SelectionChrome(...))` so the fill
/// covers the full List row including any DisclosureGroup chevron gutter — not
/// just the label area. `trailing` is an optional ViewBuilder slot for callers
/// that need to render content at the right edge of the row.
struct SelectableRow<Trailing: View>: View {
    let title: String
    let symbol: String
    let tag: SelectionTag
    @Binding var selection: SidebarSelection
    let accent: Color?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        symbol: String,
        tag: SelectionTag,
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
        tag.matches(selection)
    }

    var body: some View {
        // Pure content — tap + drag are driven by `List(selection:)` +
        // `.onMove` at the SidebarView level via the row's `.tag(...)`.
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isSelected ? Color.accentColor : (accent ?? .primary))
                .frame(width: 16, height: 16, alignment: .center)
            Text(title)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .brightness(isSelected ? 0.10 : 0)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, 4)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
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
            case .flat: return EdgeInsets(top: 2, leading: 11, bottom: 2, trailing: 11)
            case .disclosure: return EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 11)
            }
        }
    }

    let isSelected: Bool
    var style: Style = .flat

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
        HStack(spacing: 4) {
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
