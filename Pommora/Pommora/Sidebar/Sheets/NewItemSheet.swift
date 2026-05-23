import SwiftUI

/// Minimal stub — designed UI ships in a follow-up plan. Routes the
/// SidebarSheet enum case to a build-clean destination.
///
/// ParadigmV2 (Task 8.2): Items now belong to ItemType + (optional) ItemCollection.
/// Designed creation UI lands with the Items-side surface plan; this stub keeps
/// the `.newItem` SidebarSheet case routed somewhere that compiles.
struct NewItemSheet: View {
    let collection: ItemCollection?
    let type: ItemType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Create Item",
                systemImage: "doc.badge.plus",
                description: Text("UI ships in a follow-up plan. Data layer is live; create stub entities via tests or by editing the nexus folder directly.")
            )
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 380, height: 240)
    }
}
