import SwiftUI

/// Minimal stub — designed UI ships in a follow-up plan. Routes the
/// SidebarSheet enum case to a build-clean destination.
struct NewItemCollectionSheet: View {
    let type: ItemType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Create Item Collection",
                systemImage: "tray",
                description: Text(
                    "UI ships in a follow-up plan. Data layer is live; create stub entities via tests or by editing the nexus folder directly."
                )
            )
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 380, height: 240)
    }
}
