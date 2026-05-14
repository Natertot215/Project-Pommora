//
//  ContentView.swift
//  Pommora
//

import SwiftUI

struct ContentView: View {
    @State private var inspectorPresented = false

    var body: some View {
        NavigationSplitView {
            List {
                // sidebar tree lands here in v0.1
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            EmptyPane()
        }
        .inspector(isPresented: $inspectorPresented) {
            EmptyPane()
                .inspectorColumnWidth(min: 220, ideal: 280, max: 480)
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
