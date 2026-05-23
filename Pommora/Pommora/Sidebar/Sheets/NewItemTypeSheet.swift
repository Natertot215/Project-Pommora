import SwiftUI

/// Minimal stub — designed UI ships in a follow-up plan. Routes the
/// SidebarSheet enum case to a build-clean destination.
struct NewItemTypeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Create Item Type",
                systemImage: "tray.full",
                description: Text("UI ships in a follow-up plan. Data layer is live; create stub entities via tests or by editing the nexus folder directly.")
            )
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 380, height: 240)
    }
}
