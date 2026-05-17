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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace:                  NewSpaceSheet()
            case .newTopic:                  NewTopicSheet()
            case .newSubtopic(let t):        NewSubtopicSheet(parent: t)
            case .newVault:                  NewVaultSheet()
            case .newCollection(let v):      NewCollectionSheet(vault: v)
            case .newPage(let c, let v):     NewPageSheet(parent: .collection(c, vault: v))
            case .newPageInVault(let v):     NewPageSheet(parent: .vaultRoot(v))
            case .newItem(let c, let v):     NewItemSheet(collection: c, vault: v)
            case .editTopicParents(let t):   EditTopicParentsSheet(topic: t)
            case .editIcon(let target):      IconPickerSheet(target: target)
            case .editColor(let s):          ColorPickerSheet(space: s)
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
        case .deleteSpace(let s)?:      return "Delete Space \"\(s.title)\"?"
        case .deleteTopic(let t, _)?:   return "Delete Topic \"\(t.title)\"?"
        case .deleteSubtopic(let s)?:   return "Delete Sub-topic \"\(s.title)\"?"
        case .deleteVault(let v, _)?:   return "Delete Vault \"\(v.title)\"?"
        case .deleteCollection(let c)?: return "Delete Collection \"\(c.title)\"?"
        case nil: return ""
        }
    }

    private func confirmationMessage(for confirmation: SidebarConfirmation) -> String {
        switch confirmation {
        case .deleteSpace: return "This action cannot be undone."
        case .deleteTopic(_, let count): return count > 0
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
                Task { try? await spaceManager.delete(s); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteTopic(let t, let count):
            if count > 0 {
                Button("Delete & Promote Sub-topics", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: true); confirmingDelete = nil }
                }
                Button("Delete All", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: false); confirmingDelete = nil }
                }
            } else {
                Button("Delete", role: .destructive) {
                    Task { try? await topicManager.deleteTopic(t, promotingSubtopics: true); confirmingDelete = nil }
                }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteSubtopic(let s):
            Button("Delete", role: .destructive) {
                Task { try? await topicManager.deleteSubtopic(s); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteVault(let v, _):
            Button("Delete", role: .destructive) {
                Task { try? await vaultManager.deleteVault(v); confirmingDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        case .deleteCollection(let c):
            Button("Delete", role: .destructive) {
                Task { try? await vaultManager.deleteCollection(c); confirmingDelete = nil }
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
            }
        } header: { EmptyView() }
    }

    private func iconFor(_ key: String) -> String {
        switch key {
        case "homepage": return "house"
        case "calendar": return "calendar"
        case "recents":  return "clock"
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

struct SelectableRow: View {
    let title: String
    let symbol: String
    let tag: SelectionTag
    @Binding var selection: SidebarSelection
    let accent: Color?
    let onSelect: () -> Void

    var isSelected: Bool {
        tag.matches(selection)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? Color.accentColor : (accent ?? .primary))
                .frame(width: 16, alignment: .leading)
            Text(title)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .brightness(isSelected ? 0.12 : 0)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.11))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 2)
                : nil
        )
    }
}

// MARK: - SectionHeader

/// Section header strip used by Spaces / Topics / Vaults: secondary-styled title,
/// trailing "+" button to open the corresponding "New" sheet, and a section-wide
/// right-click context menu offering the same action.
private struct SectionHeader: View {
    let title: String
    let onAdd: () -> Void

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
        }
        .contextMenu {
            Button("New") { onAdd() }
        }
    }
}
