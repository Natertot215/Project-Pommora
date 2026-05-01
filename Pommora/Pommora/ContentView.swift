import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""
    @State private var inspectorPresented: Bool = false
    @State private var contentCollapsed: Bool = false

    private static let inspectorIdealWidth: CGFloat = 280
    private static let contentIdealWidth: CGFloat = 280

    var body: some View {
        NavigationSplitView {
            SidebarView(searchText: $searchText)
        } content: {
            Color.clear
                .overlay(alignment: .topLeading) {
                    HoverRevealButton(
                        systemImage: "sidebar.left",
                        help: "Collapse content column"
                    ) {
                        contentCollapsed = true
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: contentCollapsed ? 0 : 220,
                    ideal: contentCollapsed ? 0 : Self.contentIdealWidth,
                    max: contentCollapsed ? 0 : 600
                )
        } detail: {
            Color.clear
                .overlay(alignment: .topLeading) {
                    if contentCollapsed {
                        HoverRevealButton(
                            systemImage: "sidebar.left",
                            help: "Expand content column"
                        ) {
                            contentCollapsed = false
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !inspectorPresented {
                        HoverRevealButton(
                            systemImage: "sidebar.right",
                            help: "Show inspector"
                        ) {
                            inspectorPresented = true
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .inspector(isPresented: $inspectorPresented) {
            InspectorView()
                .overlay(alignment: .topLeading) {
                    HoverRevealButton(
                        systemImage: "sidebar.right",
                        help: "Hide inspector"
                    ) {
                        inspectorPresented = false
                    }
                }
                .inspectorColumnWidth(
                    min: 220,
                    ideal: Self.inspectorIdealWidth,
                    max: 420
                )
        }
        .animation(.easeInOut(duration: 0.25), value: inspectorPresented)
        .animation(.easeInOut(duration: 0.2), value: contentCollapsed)
    }
}

#Preview {
    ContentView()
}
