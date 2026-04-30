import SwiftUI

// MARK: - Button (styles)
// swiftinterface (SwiftUI): 21934: public struct Button<Label> : SwiftUICore.View where Label : SwiftUICore.View
struct ButtonExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Bordered") {}
                .buttonStyle(.bordered)
            Button("Bordered Prominent") {}
                .buttonStyle(.borderedProminent)
            Button("Plain") {}
                .buttonStyle(.plain)
            Button {
                // action
            } label: {
                Label("With Label", systemImage: "sparkles")
            }
        }
    }
}

// MARK: - Toggle
// swiftinterface (SwiftUI): 4916: public struct Toggle<Label> : SwiftUICore.View where Label : SwiftUICore.View
struct ToggleExample: View {
    @State private var isOn: Bool = true
    var body: some View {
        Form {
            Toggle("Enabled", isOn: $isOn)
            Toggle(isOn: $isOn) {
                Label("With icon", systemImage: "bolt")
            }
        }
    }
}

#Preview("Button") { ButtonExample().padding().frame(width: 280) }
#Preview("Toggle") { ToggleExample().padding().frame(width: 280) }
