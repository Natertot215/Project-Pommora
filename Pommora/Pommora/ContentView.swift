//
//  ContentView.swift
//  Pommora
//

import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case top(Int)
    case space(Int)
    case collection(Int)
    case member(collection: Int, member: Int)
}

struct ContentView: View {
    @State private var inspectorPresented = false
    @State private var selected: SidebarItem? = .top(0)
    @State private var searchQuery = ""
    @State private var spacesExpanded = true
    @State private var collectionsExpanded = true
    @State private var collectionExpansion: [Int: Bool] = [0: false, 1: false, 2: false]

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        Label("Item \(i + 1)", systemImage: "square.dashed")
                            .tag(SidebarItem.top(i))
                    }
                }

                Section(isExpanded: $spacesExpanded) {
                    ForEach(0..<3, id: \.self) { i in
                        Label("Space \(i + 1)", systemImage: "square.dashed")
                            .tag(SidebarItem.space(i))
                    }
                } header: {
                    Text("Spaces")
                        .foregroundStyle(.secondary)
                }

                Section(isExpanded: $collectionsExpanded) {
                    ForEach(0..<3, id: \.self) { c in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { collectionExpansion[c] ?? false },
                                set: { newValue in
                                    withAnimation(.smooth(duration: 0.25)) {
                                        collectionExpansion[c] = newValue
                                    }
                                }
                            )
                        ) {
                            ForEach(0..<3, id: \.self) { m in
                                Label("Item \(m + 1)", systemImage: "square.dashed")
                                    .tag(SidebarItem.member(collection: c, member: m))
                            }
                        } label: {
                            Label("Collection \(c + 1)", systemImage: "square.dashed")
                                .tag(SidebarItem.collection(c))
                        }
                    }
                } header: {
                    Text("Collections")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .environment(\.sidebarRowSize, .medium)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 8) {
                SidebarSearchField(text: $searchQuery)
                    .padding(.horizontal, 10)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 330)
        } detail: {
            EmptyPane()
        }
        .inspector(isPresented: $inspectorPresented) {
            Color.clear
                .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.smooth(duration: 0.30)) {
                                inspectorPresented.toggle()
                            }
                        } label: {
                            Label("Toggle Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Toggle Inspector")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
    }
}

private struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private struct EmptyPane: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
