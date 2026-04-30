import SwiftUI

// MARK: - VStack
// swiftinterface (SwiftUICore): 1128: @frozen public struct VStack<Content> : SwiftUICore.View where Content : SwiftUICore.View
struct LayoutVStackExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First")
            Text("Second")
            Text("Third")
        }
    }
}

// MARK: - HStack
// swiftinterface (SwiftUICore): 5404: @frozen public struct HStack<Content> : SwiftUICore.View where Content : SwiftUICore.View
struct LayoutHStackExample: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Left")
            Spacer()
            Text("Right")
        }
    }
}

// MARK: - ZStack
// swiftinterface (SwiftUICore): 341: @frozen public struct ZStack<Content> : SwiftUICore.View where Content : SwiftUICore.View
struct LayoutZStackExample: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.accentColor.opacity(0.15)
            Text("Overlay")
                .padding()
        }
    }
}

// MARK: - Spacer
// swiftinterface (SwiftUICore): 3419: @frozen public struct Spacer
struct LayoutSpacerExample: View {
    var body: some View {
        HStack {
            Text("Pinned left")
            Spacer()
            Text("Pinned right")
        }
    }
}

// MARK: - Divider
// swiftinterface (SwiftUI): 8816: public struct Divider : SwiftUICore.View
struct LayoutDividerExample: View {
    var body: some View {
        VStack {
            Text("Above")
            Divider()
            Text("Below")
        }
    }
}

#Preview("VStack") { LayoutVStackExample().padding() }
#Preview("HStack") { LayoutHStackExample().padding() }
#Preview("ZStack") { LayoutZStackExample().frame(width: 200, height: 120) }
#Preview("Spacer") { LayoutSpacerExample().padding() }
#Preview("Divider") { LayoutDividerExample().padding() }
