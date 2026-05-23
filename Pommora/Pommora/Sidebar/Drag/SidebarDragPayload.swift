import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// In-app drag payload for sidebar reorder (v0.2.8.0). One shared envelope
/// carrying the entity's kind, ID, and parent container ID (`nil` for top-tier
/// rows). A single nexusID gate rejects cross-window drops.
///
/// The Transferable representation is JSON over a Pommora-only UTType, so
/// dropping into Finder or external apps produces no usable payload — exactly
/// what we want for v1.
struct SidebarDragPayload: Codable, Sendable, Transferable {
    enum Kind: String, Codable, Sendable {
        case space
        case topic
        case project
        case vault
        case collection
        case page
        case item
    }

    let kind: Kind
    let id: String
    /// Parent container ID — nil for top-tier rows (Space / Topic / Vault).
    /// For Project this is the parent Topic.id. For Collection this is the
    /// parent Vault.id. For a Page nested in a Collection this is the
    /// Collection.id; for a vault-root Page it is the Vault.id with
    /// `isVaultRoot = true`.
    let containerID: String?
    let isVaultRoot: Bool
    let nexusID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pommoraSidebarDrag)
    }
}

extension UTType {
    /// Custom Pommora-only UTType. Not registered in Info.plist intentionally —
    /// it's an in-app channel that external apps must not be able to receive.
    /// `nonisolated` lets the constant satisfy `Transferable`'s nonisolated
    /// `transferRepresentation` requirement (UTType is Sendable, so no
    /// `(unsafe)` is needed).
    nonisolated static let pommoraSidebarDrag = UTType(
        exportedAs: "com.pommora.sidebar-drag"
    )
}
