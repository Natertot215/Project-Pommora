import Foundation

/// Validates whether a `SidebarDragPayload` can drop onto a given destination
/// row (v0.2.8.0). V1 is reorder-only: same kind + same container.
///
/// Cross-container moves (Page → different Collection, Collection → different
/// Vault, Project → different Topic) stay in the right-click "Move to…" menu
/// for now; they're not delivered through drag in this ship.
enum DragValidator {
    /// Target description — the row receiving the drop.
    struct Target {
        let kind: SidebarDragPayload.Kind
        let id: String
        /// Parent container of the target. nil for top-tier rows.
        let containerID: String?
        /// Whether the target's parent (for Pages/Items) is a vault root rather
        /// than a Collection. Ignored for other kinds.
        let isVaultRoot: Bool
        let nexusID: String
    }

    /// Returns `true` iff `payload` may legally drop onto `target` under v1
    /// reorder-only rules:
    /// - Same nexus.
    /// - Same kind.
    /// - Same parent container (both nil for top-tier; both equal otherwise).
    /// - For Pages/Items, both must agree on vault-root vs collection-scoped.
    /// - Source ≠ destination (don't drop on self).
    static func canAccept(_ payload: SidebarDragPayload, on target: Target) -> Bool {
        guard payload.nexusID == target.nexusID else { return false }
        guard payload.kind == target.kind else { return false }
        guard payload.id != target.id else { return false }
        guard payload.containerID == target.containerID else { return false }
        // Pages and Items can sit either in a vault root or in a Collection;
        // the two are not interchangeable, so demand agreement.
        if payload.kind == .page || payload.kind == .item {
            guard payload.isVaultRoot == target.isVaultRoot else { return false }
        }
        return true
    }
}
