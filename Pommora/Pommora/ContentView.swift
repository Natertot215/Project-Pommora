//
//  ContentView.swift
//  Pommora
//

import SwiftUI

struct ContentView: View {
    @State private var inspectorPresented = false

    var body: some View {
        NavigationSplitView {
            Color.clear
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            Color.clear
                .inspector(isPresented: $inspectorPresented) {
                    Color.clear
                        .inspectorColumnWidth(min: 220, ideal: 280, max: 480)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            inspectorPresented.toggle()
                        } label: {
                            Label("Toggle Inspector", systemImage: "sidebar.right")
                        }
                    }
                }
        }
        .frame(minWidth: 960, minHeight: 560)
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
