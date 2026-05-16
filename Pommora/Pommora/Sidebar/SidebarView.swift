//
//  SidebarView.swift
//  Pommora
//

import SwiftUI

/// Scaffold sidebar — hardcoded placeholder structure showing the three
/// top-level concepts: loose Items, the Spaces section, and the Collections
/// section with nested collection folders. Real data plumbing (FolderTree,
/// SidebarNode, SidebarRow) is parked until the entity layer wires in.
///
/// Selection chrome is custom: gray-at-11% rounded fill + accent foreground
/// on icon + text. Required because `List(selection:)` paints opaque accent.
struct SidebarView: View {
    @State private var selection: String?
    @State private var spacesExpanded = true
    @State private var collectionsExpanded = true
    @State private var collectionExpanded: [Bool] = [true, true, true]

    var body: some View {
        List {
            ForEach(0..<3, id: \.self) { index in
                SelectableRow(
                    title: "Item",
                    symbol: "list.bullet.rectangle",
                    tag: "item-\(index)",
                    selection: $selection
                )
            }

            Section(isExpanded: $spacesExpanded) {
                SelectableRow(title: "Space One", symbol: "square.stack",
                              tag: "space-one", selection: $selection)
                SelectableRow(title: "Space Two", symbol: "square.stack",
                              tag: "space-two", selection: $selection)
                SelectableRow(title: "Space Three", symbol: "square.stack",
                              tag: "space-three", selection: $selection)
            } header: {
                Text("Spaces").foregroundStyle(.secondary)
            }

            Section(isExpanded: $collectionsExpanded) {
                ForEach(collectionExpanded.indices, id: \.self) { collectionIndex in
                    DisclosureGroup(isExpanded: $collectionExpanded[collectionIndex]) {
                        ForEach(0..<3, id: \.self) { placeholderIndex in
                            SelectableRow(
                                title: "Placeholder",
                                symbol: "doc.text",
                                tag: "placeholder-\(collectionIndex)-\(placeholderIndex)",
                                selection: $selection
                            )
                        }
                    } label: {
                        SelectableRow(
                            title: "Collection",
                            symbol: "folder",
                            tag: "collection-\(collectionIndex)",
                            selection: $selection
                        )
                    }
                }
            } header: {
                Text("Collections").foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

private struct SelectableRow: View {
    let title: String
    let symbol: String
    let tag: String
    @Binding var selection: String?

    private var isSelected: Bool { selection == tag }

    private var rowBackground: AnyView? {
        guard isSelected else { return nil }
        return AnyView(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.gray.opacity(0.11))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .brightness(isSelected ? 0.0 : 0)
                .frame(width: 16, alignment: .leading)
            Text(title)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .brightness(isSelected ? 0.11 : 0)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selection = tag }
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowBackground(rowBackground)
    }
}
