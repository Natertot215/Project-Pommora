import SwiftUI

struct ColorPickerSheet: View {
    let area: Area
    @Environment(\.dismiss) private var dismiss
    @Environment(AreaManager.self) private var areaManager
    @State private var draft: AreaColor?

    init(area: Area) {
        self.area = area
        _draft = State(initialValue: area.color)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Color for \"\(area.title)\"")
                .font(.headline)
            AreaColorPicker(color: $draft)
                .padding()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    Task {
                        do { try await areaManager.updateColor(area, to: draft) } catch
                        { /* pendingError set by manager; toast surfaces */  }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 320, height: 220)
    }
}
