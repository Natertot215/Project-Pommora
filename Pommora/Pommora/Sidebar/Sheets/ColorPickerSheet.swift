import SwiftUI

struct ColorPickerSheet: View {
    let space: Space
    @Environment(\.dismiss) private var dismiss
    @Environment(SpaceManager.self) private var spaceManager
    @State private var draft: SpaceColor

    init(space: Space) {
        self.space = space
        _draft = State(initialValue: space.color)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Color for \"\(space.title)\"")
                .font(.headline)
            SpaceColorPicker(color: $draft)
                .padding()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    Task {
                        try? await spaceManager.updateColor(space, to: draft)
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
