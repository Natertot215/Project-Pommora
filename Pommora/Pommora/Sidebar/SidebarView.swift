//
//  SidebarView.swift
//  Pommora
//

/// Selection chrome painted via `.listRowBackground` at the row-file level so
/// the fill covers the full List row (including any DisclosureGroup chevron
/// gutter). Inset per locked spec — 11pt horizontal + 2pt vertical from row
/// edges by default for flat rows. DisclosureGroup-wrapped rows pass
/// `.disclosure` style to flush the leading edge so chrome covers the chevron.
import SwiftUI

/// Five-section sidebar: Saved (pinned-headerless) / Spaces / Topics / Items / Pages. Rows extracted to *Row.swift files; sheets at Sheets/*Sheet.swift.
struct SidebarView: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(SavedConfigManager.self) private var savedConfigManager

    @Binding var selection: SidebarSelection

    @State private var editingID: String? = nil
    @State private var presentedSheet: SidebarSheet? = nil
    @State private var confirmingDelete: SidebarConfirmation? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Toast surfaces CRUD failures via each manager's pendingError.
            // Lives ABOVE the List so it doesn't touch the load-bearing
            // Section / SectionHeader layout inside.
            SidebarToast()
            List {
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
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
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

struct SavedSection: View {
    @Binding var selection: SidebarSelection
    @Environment(SavedConfigManager.self) private var savedConfigManager

    var body: some View {
        Section {
            ForEach(savedConfigManager.config.items) { item in
                SelectableRow(
                    title: item.label,
                    symbol: iconFor(item.key),
                    tag: SelectionTag.savedKey(item.key),
                    selection: $selection,
                    accent: nil,
                    onSelect: { selection = .savedKey(item.key) }
                )
                .listRowBackground(
                    SelectionChrome(
                        isSelected: SelectionTag.savedKey(item.key).matches(selection)
                    )
                )
            }
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
            }
            // Reorder is wired per-row via `.reorderable` (v0.2.8 Phase 2);
            // `.onMove` is omitted on purpose so List doesn't draw its native
            // blue insertion line. See `Sidebar/Drag/ReorderableRow.swift`.
        } header: {
            SectionHeader(title: "Spaces") {
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
            }
            // Reorder wired per-row via `.reorderable` (v0.2.8 Phase 2).
        } header: {
            SectionHeader(title: "Topics") {
                presentedSheet = .newTopic
            }
        }
    }
}

struct ItemsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(ItemTypeManager.self) private var itemTypeManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(itemTypeManager.types) { itemType in
                ItemTypeRow(
                    itemType: itemType,
                    selection: $selection
                )
            }
        } header: {
            // Phase 8 stub: literal "Items" label (no SettingsManager read yet —
            // Items-side label wiring lands with the real Items UI plan, per
            // Task 8.5 spec).
            SectionHeader(title: "Items") {
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

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(vaultManager.types) { pageType in
                PageTypeRow(
                    pageType: pageType,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
            // Reorder wired per-row via `.reorderable` (v0.2.8 Phase 2).
        } header: {
            // Task 7.3 — section header text comes from SettingsManager
            // (`sidebar_sections.pages`, default "Pages"). Items section header
            // wires identically when Phase 8.1 ships ItemsSection.
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
    let onSelect: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        symbol: String,
        tag: SelectionTag,
        selection: Binding<SidebarSelection>,
        accent: Color?,
        onSelect: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.symbol = symbol
        self.tag = tag
        self._selection = selection
        self.accent = accent
        self.onSelect = onSelect
        self.trailing = trailing
    }

    var isSelected: Bool {
        tag.matches(selection)
    }

    var body: some View {
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
        // .simultaneousGesture instead of .onTapGesture so taps don't claim
        // mouse-down exclusively — leaves the row edges available as drag
        // initiation zones for List.onMove. Partial fix: drag works on the
        // outer margins of each row, not on the label content itself.
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
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
                // This forces the permanent native gray sidebar selection
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
