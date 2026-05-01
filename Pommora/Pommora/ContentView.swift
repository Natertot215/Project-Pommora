import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(searchText: $searchText)
        } content: {
            Color.clear
        } detail: {
            Color.clear
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

#Preview {
    ContentView()
}
