import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(searchText: $searchText)
        } content: {
            ContentUnavailableView(
                "No selection",
                systemImage: "square.dashed",
                description: Text("Select an item from the sidebar.")
            )
        } detail: {
            ContentUnavailableView(
                "No detail",
                systemImage: "doc",
                description: Text("Detail will appear here.")
            )
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

#Preview {
    ContentView()
}
