import SwiftUI

struct SidebarView: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(PageTypeManager.self) private var vaultManager

    @Binding var selection: SidebarSelection

    @State private var editingID: String? = nil
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
                SpacesSection(
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                TopicsSection(
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                ItemsSection(
                    selection: $selection,
                    presentedSheet: $presentedSheet
                )
                VaultsSection(
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selectedTag) { _, newTag in
                if let newTag, let resolved = SidebarSelection(tag: newTag) {
                    if selection != resolved { selection = resolved }
                } else if newTag == nil, selection != .none {
                    selection = .none
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
            .background(NSTableSelectionStyleSuppressor()) // Nathan's Note: This is what prevents the double-accent fill and allows for the finder-like quartenary opacity.
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace: NewSpaceSheet()
            case .newTopic: NewTopicSheet()
            case .newProject(let t): NewProjectSheet(parent: t)
            case .newPageType: NewPageTypeSheet()
            case .newCollection(let v): NewPageCollectionSheet(vault: v)
            case .newPage(let c, let v): NewPageSheet(parent: .collection(c, vault: v))
            case .newPageInPageType(pageType: let v): NewPageSheet(parent: .vaultRoot(v))
            case .newItemType: NewItemTypeSheet()
            case .newItemCollection(let t): NewItemCollectionSheet(type: t)
            case .newItem(let c, let t): NewItemSheet(collection: c, type: t)
            case .editTopicParents(let t): EditTopicParentsSheet(topic: t)
            case .editIcon(let target): IconPickerSheet(target: target)
            case .editColor(let s): ColorPickerSheet(space: s)
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
        case .deleteSpace(let s)?: return "Delete Space \"\(s.title)\"?"
        case .deleteTopic(let t, _)?: return "Delete Topic \"\(t.title)\"?"
        case .deleteProject(let p)?: return "Delete Project \"\(p.title)\"?"
        case .deleteVault(let v, _)?: return "Delete Vault \"\(v.title)\"?"
        case .deleteCollection(let c)?: return "Delete Collection \"\(c.title)\"?"
        case nil: return ""
        }
    }

    private func confirmationMessage(for confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .deleteSpace: return "This action cannot be undone."
        case .deleteTopic(_, let count):
            return count > 0
                ? "Contains \(count) Project(s). Promote them or delete all?"
                : "This action cannot be undone."
        case .deleteProject: return "This action cannot be undone."
        case .deleteVault(_, let cols): return "Contains \(cols) Collection(s). All contents will be deleted."
        case .deleteCollection: return "All Pages and Items inside will be deleted."
        }
    }

    @ViewBuilder
    private func confirmationButtons(for confirmation: SidebarConfirmation) -> some View {
        switch confirmation {
        case .deleteSpace(let s):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await spaceManager.delete(s) } catch { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteTopic(let t, let count):
            if count > 0 {
                Button("Delete & Promote Projects", role: .destructive) {
                    Task {
                        do { try await topicManager.deleteTopic(t, promotingProjects: true) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        confirmingDelete = nil
                    }
                }
                Button("Delete All", role: .destructive) {
                    Task {
                        do { try await topicManager.deleteTopic(t, promotingProjects: false) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        confirmingDelete = nil
                    }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await topicManager.deleteTopic(t, promotingProjects: true) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        confirmingDelete = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteProject(let p):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await topicManager.deleteProject(p) } catch
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

struct SpacesSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(spaceManager.spaces) { space in
                SpaceRow(
                    space: space,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                .tag(SelectionTag.space(space.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    spaceManager.reorderSpaces(fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            SectionHeader(title: settingsManager.settings.labels.sidebarSections.spaces) {
                presentedSheet = .newSpace
            }
        }
    }
}

struct TopicsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(TopicManager.self) private var topicManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(topicManager.topics) { topic in
                TopicRow(
                    topic: topic,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
                .tag(SelectionTag.topic(topic.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    topicManager.reorderTopics(fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            SectionHeader(title: settingsManager.settings.labels.sidebarSections.topics) {
                presentedSheet = .newTopic
            }
        }
    }
}

struct ItemsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(NexusManager.self) private var nexusManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(itemTypeManager.types) { itemType in
                ItemTypeRow(
                    itemType: itemType,
                    selection: $selection,
                    nexus: nexusManager.currentNexus ?? Nexus(id: "", rootURL: URL(filePath: "/")),
                    index: nexusManager.currentIndex
                )
                .tag(SelectionTag.itemType(itemType.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    itemTypeManager.reorderItemTypes(fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            SectionHeader(title: settingsManager.settings.labels.sidebarSections.items) {
                presentedSheet = .newItemType
            }
        }
    }
}

struct VaultsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(NexusManager.self) private var nexusManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(vaultManager.types) { pageType in
                PageTypeRow(
                    pageType: pageType,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete,
                    nexus: nexusManager.currentNexus ?? Nexus(id: "", rootURL: URL(filePath: "/")),
                    index: nexusManager.currentIndex
                )
                .tag(SelectionTag.pageType(pageType.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    vaultManager.reorderPageTypes(fromOffsets: source, toOffset: destination)
                }
            }
        } header: {
            SectionHeader(title: settingsManager.settings.labels.sidebarSections.pages) {
                presentedSheet = .newPageType
            }
        }
    }
}

// MARK: - SelectableRow (updated to use SelectionTag)

/// Self-contained sidebar row content. Selection chrome is painted at the
/// row-file level via `.listRowBackground(SelectionChrome(...))` so the fill
/// covers the full List row including any DisclosureGroup chevron gutter — not
/// just the label area. `trailing` is an optional ViewBuilder slot for callers
/// that need to render content at the right edge of the row (e.g. TopicRow's
/// ParentSpaceTags dots).
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

/// Section header strip used by Spaces / Topics / Vaults: secondary-styled title,
/// trailing "+" button that fades in on hover (matching the disclosure-chevron's
/// hover affordance), and a section-wide right-click context menu offering the
/// same action regardless of hover state.
private struct SectionHeader: View {
    let title: String
    let onAdd: () -> Void

    @State private var hovered: Bool = false

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
        }
    }
}
