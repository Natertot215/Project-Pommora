import SwiftUI

// MARK: - NavigationStack
// swiftinterface (SwiftUI): 14608: public struct NavigationStack<Data, Root> : SwiftUICore.View where Root : SwiftUICore.View
struct NavigationStackExample: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Push detail", value: "Detail")
            }
            .navigationDestination(for: String.self) { value in
                Text("Pushed: \(value)")
            }
            .navigationTitle("Stack")
        }
    }
}

// MARK: - NavigationSplitView (.prominentDetail)
// swiftinterface (SwiftUI): 20410: public struct NavigationSplitView<Sidebar, Content, Detail> : SwiftUICore.View where Sidebar : SwiftUICore.View, Content : SwiftUICore.View, Detail : SwiftUICore.View
// See L-003: always use `.prominentDetail` so sidebar/content resize independently.
struct NavigationSplitViewExample: View {
    var body: some View {
        NavigationSplitView {
            List { Text("Sidebar row") }
        } content: {
            Text("Content column")
        } detail: {
            Text("Detail column")
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

// MARK: - NavigationLink (value-based)
// swiftinterface (SwiftUI): 11185: public struct NavigationLink<Label, Destination> : SwiftUICore.View where Label : SwiftUICore.View, Destination : SwiftUICore.View
struct NavigationLinkExample: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(value: 1) { Label("One", systemImage: "1.circle") }
                NavigationLink(value: 2) { Label("Two", systemImage: "2.circle") }
            }
            .navigationDestination(for: Int.self) { Text("Value \($0)") }
        }
    }
}

// MARK: - TabView
// swiftinterface (SwiftUI): 2483: public struct TabView<SelectionValue, Content> : SwiftUICore.View where SelectionValue : Swift.Hashable, Content : SwiftUICore.View
struct TabViewExample: View {
    var body: some View {
        TabView {
            Text("First").tabItem { Label("First", systemImage: "1.square") }
            Text("Second").tabItem { Label("Second", systemImage: "2.square") }
        }
    }
}

#Preview("NavigationStack") { NavigationStackExample().frame(width: 320, height: 220) }
#Preview("NavigationSplitView") { NavigationSplitViewExample().frame(width: 600, height: 320) }
#Preview("NavigationLink") { NavigationLinkExample().frame(width: 320, height: 220) }
#Preview("TabView") { TabViewExample().frame(width: 360, height: 220) }
