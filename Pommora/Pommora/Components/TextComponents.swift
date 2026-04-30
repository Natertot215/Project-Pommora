import SwiftUI

// MARK: - Text
// swiftinterface (SwiftUICore): 18180: @frozen public struct Text : Swift.Equatable, Swift.Sendable
struct TextExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Headline").font(.headline)
            Text("Body text").font(.body)
            Text("Caption").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Label
// swiftinterface (SwiftUI): 23050: public struct Label<Title, Icon> : SwiftUICore.View where Title : SwiftUICore.View, Icon : SwiftUICore.View
struct LabelExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Inbox", systemImage: "tray")
            Label("Starred", systemImage: "star")
                .imageScale(.large)
            Label {
                Text("Custom title").bold()
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - TextField
// swiftinterface (SwiftUI): 5193: public struct TextField<Label> : SwiftUICore.View where Label : SwiftUICore.View
struct TextFieldExample: View {
    @State private var name: String = ""
    var body: some View {
        Form {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview("Text") { TextExample().padding() }
#Preview("Label") { LabelExample().padding() }
#Preview("TextField") { TextFieldExample().padding().frame(width: 280) }
