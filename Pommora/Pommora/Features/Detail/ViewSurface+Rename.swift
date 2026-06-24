import SwiftUI

extension ViewSurface {
    var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    func renameTitle(_ target: RowTarget) -> String {
        switch target {
        case .page(let item): return item.page.title
        case .container(let ref): return ref.title
        }
    }

    func renameKindLabel(_ target: RowTarget) -> String {
        switch target {
        case .page: return "Page"
        case .container(let ref): return ref.kindLabel
        }
    }

    func beginRename(_ target: RowTarget) {
        renameDraft = renameTitle(target)
        renameTarget = target
    }

    func commitRename() {
        guard let target = renameTarget else { return }
        let newName = renameDraft
        renameTarget = nil
        guard !newName.isEmpty, newName != renameTitle(target) else { return }
        Task {
            do {
                switch target {
                case .container(let ref):
                    try await renameContainer(ref, to: newName)
                case .page(let item):
                    // Route purely off the stamped parent — uniform across scopes.
                    // `.collectionRoot` can't occur in collection scope but is harmless.
                    switch item.parent {
                    case .collection(let coll, let t):
                        try await contentManager.renamePage(item.page, to: newName, in: coll, pageCollection: t)
                    case .set(let set, let coll, let t):
                        try await contentManager.renamePage(
                            item.page, to: newName, in: set, collection: coll, pageCollection: t)
                    case .collectionRoot(let t):
                        try await contentManager.renamePage(item.page, to: newName, inCollectionRoot: t)
                    }
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    /// Renames a container via its kind's manager (Collection or Set).
    private func renameContainer(_ ref: ContainerRef, to newName: String) async throws {
        switch ref {
        case .collection(let coll):
            try await collectionManager.renamePageCollection(coll, to: newName)
        case .set(let set):
            try await pageSetManager.renamePageSet(set, to: newName)
        }
    }
}
