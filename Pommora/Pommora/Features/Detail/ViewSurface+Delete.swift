import SwiftUI

extension ViewSurface {
    /// The active container-delete confirmation payload (vault: single Collection
    /// delete; collection: two-mode Set delete), nil when nothing is pending.
    var deleteConfirmation: DeleteConfirmation? {
        guard let ref = deleteTarget else { return nil }
        return scope.deleteConfirmation(for: ref, settings: settingsManager)
    }

    var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    /// The confirmation dialog's buttons. `single` → one destructive Collection
    /// delete; `setTwoMode` → the two-mode Set delete (Set only vs. Set and Pages).
    @ViewBuilder
    func deleteConfirmationActions(_ confirmation: DeleteConfirmation) -> some View {
        switch confirmation.mode {
        case .single(let coll):
            Button("Delete", role: .destructive) {
                Task {
                    do { try await pageTypeManager.deletePageCollection(coll) } catch {}
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        case .setTwoMode(let set, let coll):
            Button("Delete Set Only") {
                Task {
                    do {
                        try await pageSetManager.deletePageSet(set, mode: .setOnly)
                        // Rehomed Pages land in the Collection root on disk + in
                        // the index; refresh the cache so they surface now.
                        await contentManager.loadAll(for: coll)
                    } catch {}
                    deleteTarget = nil
                }
            }
            Button("Delete Set and Pages", role: .destructive) {
                Task {
                    do {
                        try await pageSetManager.deletePageSet(set, mode: .withPages)
                        await contentManager.loadAll(for: coll)
                    } catch {}
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
    }

    /// Direct page delete (containers route through the confirmation dialog). Routes
    /// purely off the stamped parent — uniform across scopes; `.vaultRoot` can't
    /// occur in collection scope but is harmless.
    func delete(_ target: RowTarget) async {
        guard case .page(let item) = target else { return }
        do {
            switch item.parent {
            case .collection(let coll, _):
                try await contentManager.deletePage(item.page, in: coll)
            case .set(let set, _, _):
                try await contentManager.deletePage(item.page, in: set)
            case .vaultRoot(let t):
                try await contentManager.deletePage(item.page, inVaultRoot: t)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
