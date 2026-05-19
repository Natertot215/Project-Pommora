import Foundation

/// Routing value carried into `WindowGroup(for: EntityRef.self)` to spawn
/// a standalone preview window for a full-frame-eligible entity. Items
/// and Agenda entries are NOT cases here — they use ItemWindow popover.
/// Collection is reserved for a future enable; not currently wired into
/// the NavDropdown trigger flow.
enum EntityRef: Hashable, Codable, Sendable {
    case page(pageID: String, vaultID: String, collectionID: String?)
    case vault(vaultID: String)
    case collection(vaultID: String, collectionID: String)  // reserved
    case space(spaceID: String)
    case topic(topicID: String)
    case subtopic(subtopicID: String, parentTopicID: String)
}

extension EntityRef {
    /// Best-effort resolve an EntityStateRef into an EntityRef. Returns nil
    /// for Item/Agenda (no standalone-window representation), for Collection
    /// (not wired in v0.2.7.2), and for unknown future kinds.
    @MainActor
    init?(stateRef: EntityStateRef) {
        switch stateRef.typedKind {
        case .page:
            // PageMeta has no vaultID/collectionID fields — resolve by scanning
            // ContentManager's keyed dicts. Check collection-hosted pages first,
            // then vault-root pages (collectionID = nil).
            guard let cm = AppGlobals.contentManager else { return nil }

            // Scan pagesByCollection: collectionID → [PageMeta]
            for (collectionID, pages) in cm.pagesByCollection {
                if pages.contains(where: { $0.id == stateRef.id }) {
                    // Look up vaultID via VaultManager's collectionsByVault reverse scan.
                    guard let vm = AppGlobals.vaultManager else { return nil }
                    var vaultID: String?
                    outer: for (vid, collections) in vm.collectionsByVault {
                        for col in collections where col.id == collectionID {
                            vaultID = vid
                            break outer
                        }
                    }
                    guard let resolvedVaultID = vaultID else { return nil }
                    self = .page(pageID: stateRef.id, vaultID: resolvedVaultID, collectionID: collectionID)
                    return
                }
            }

            // Scan pagesByVaultRoot: vaultID → [PageMeta] (no collection)
            for (vaultID, pages) in cm.pagesByVaultRoot {
                if pages.contains(where: { $0.id == stateRef.id }) {
                    self = .page(pageID: stateRef.id, vaultID: vaultID, collectionID: nil)
                    return
                }
            }

            return nil

        case .vault:
            self = .vault(vaultID: stateRef.id)

        case .space:
            self = .space(spaceID: stateRef.id)

        case .topic:
            self = .topic(topicID: stateRef.id)

        case .subtopic:
            // TopicManager has no parentTopicID(for:) — derive from subtopicsByParent.
            guard let tm = AppGlobals.topicManager else { return nil }
            var parentTopicID: String?
            for (pid, subtopics) in tm.subtopicsByParent {
                if subtopics.contains(where: { $0.id == stateRef.id }) {
                    parentTopicID = pid
                    break
                }
            }
            guard let resolvedParentID = parentTopicID else { return nil }
            self = .subtopic(subtopicID: stateRef.id, parentTopicID: resolvedParentID)

        case .collection:
            return nil  // not wired in v0.2.7.2

        case .item, .agenda, .none:
            return nil
        }
    }
}
