//
//  SidebarView.swift
//  Pommora
//

import SwiftUI

/// Four-section sidebar: Saved (pinned-headerless) / Spaces / Topics / Vaults. Rows extracted to *Row.swift files; sheets at Sheets/*Sheet.swift.
struct SidebarView: View {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(VaultManager.self) private var vaultManager
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
            case .newSubtopic(let t): NewSubtopicSheet(parent: t)
            case .newVault: NewVaultSheet()
            case .newCollection(let v): NewCollectionSheet(vault: v)
            case .newPage(let c, let v): NewPageSheet(parent: .collection(c, vault: v))
            case .newPageInVault(let v): NewPageSheet(parent: .vaultRoot(v))
            case .newItem(let c, let v): NewItemSheet(collection: c, vault: v)
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
        case .deleteSubtopic(let s)?: return "Delete Sub-topic \"\(s.title)\"?"
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
                ? "Contains \(count) Sub-topic(s). Promote them or delete all?"
                : "This action cannot be undone."
        case .deleteSubtopic: return "This action cannot be undone."
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
                Button("Delete & Promote Sub-topics", role: .destructive) {
                    Task {
                        do { try await topicManager.deleteTopic(t, promotingSubtopics: true) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        confirmingDelete = nil
                    }
                }
                Button("Delete All", role: .destructive) {
                    Task {
                        do { try await topicManager.deleteTopic(t, promotingSubtopics: false) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        confirmingDelete = nil
                    }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await topicManager.deleteTopic(t, promotingSubtopics: true) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        confirmingDelete = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteSubtopic(let s):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await topicManager.deleteSubtopic(s) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteVault(let v, _):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await vaultManager.deleteVault(v) } catch
                    { /* pendingError set by manager; toast surfaces */  }
                    confirmingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteCollection(let c):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await vaultManager.deleteCollection(c) } catch
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
        } header: {
            SectionHeader(title: "Topics") {
                presentedSheet = .newTopic
            }
        }
    }
}

struct VaultsSection: View {
    @Binding var selection: SidebarSelection
    @Binding var editingID: String?
    @Binding var presentedSheet: SidebarSheet?
    @Binding var confirmingDelete: SidebarConfirmation?
    @Environment(VaultManager.self) private var vaultManager

    @State private var expanded: Bool = true

    var body: some View {
        Section(isExpanded: $expanded) {
            ForEach(vaultManager.vaults) { vault in
                VaultRow(
                    vault: vault,
                    selection: $selection,
                    editingID: $editingID,
                    presentedSheet: $presentedSheet,
                    confirmingDelete: $confirmingDelete
                )
            }
        } header: {
            SectionHeader(title: "Vaults") {
                presentedSheet = .newVault
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
        .onTapGesture { onSelect() }
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
    }
}

/// Selection chrome painted via `.listRowBackground` at the row-file level so
/// the fill covers the full List row (including any DisclosureGroup chevron
/// gutter). Inset per locked spec — 11pt horizontal + 2pt vertical from row
/// edges by default for flat rows. DisclosureGroup-wrapped rows pass
/// `.disclosure` style to flush the leading edge so chrome covers the chevron.
struct SelectionChrome: View {
    enum Style {
        case flat  // 11pt symmetric horizontal inset
        case disclosure  // 0pt leading, 11pt trailing — covers chevron

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
                .fill(Color.gray.opacity(0.10))
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
