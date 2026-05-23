import SwiftUI

struct NewItemSheet: View {
    let collection: PageCollection
    let vault: PageType
    @Environment(\.dismiss) private var dismiss

    // ParadigmV2 (Task 5.5): Items are now owned by ItemContentManager keyed on
    // ItemType + ItemCollection. PageCollection-targeted Item creation disappears
    // from the UI until Phase 6 wires the Items-side detail surface. This sheet
    // is preserved as a compile-only stub so the call sites in
    // PageCollectionDetailView + SidebarView keep wiring through.
    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item in \"\(collection.title)\"").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 380, height: 220)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        // TODO Phase 6: route through ItemContentManager.createItem once the
        // Items-side detail surface exists. Until then, surface a friendly
        // notice and dismiss without writing.
        _ = collection
        _ = vault
        _ = name
        errorMessage = "Item creation is temporarily disabled while the Items-side surface rebuilds (ParadigmV2 Phase 6)."
    }
}
