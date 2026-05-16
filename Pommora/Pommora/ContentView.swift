//
//  ContentView.swift
//  Pommora
//

import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(NexusManager.self) private var nexusManager
    @State private var inspectorPresented = false
    @State private var searchQuery = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(manager: nexusManager)
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
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth(duration: 0.30)) {
                        inspectorPresented.toggle()
                    }
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .buttonStyle(.borderless)
                .controlSize(.large)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .task {
            await nexusManager.loadOnLaunch()
        }
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
        .environment(NexusManager())
        .frame(width: 1200, height: 800)
}
