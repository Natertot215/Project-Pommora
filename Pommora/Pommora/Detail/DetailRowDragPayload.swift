import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Carried during drag in any storage-container detail-pane Table.
/// `rowID` is the entity's ULID; `zone` flags the source context so the
/// drop handler can reject cross-zone drops (the v1 reorder paradigm is
/// same-zone-only — Items can't be dragged from one Set into another in
/// this spec; cross-Set move is a follow-up).
struct DetailRowDragPayload: Codable, Equatable, Hashable, Sendable, Transferable {
    let rowID: String
    let zone: Zone

    enum Zone: String, Codable, Sendable {
        case typeRootItem       // Item directly inside an ItemType (root)
        case typeSet            // Set inside an ItemType
        case collectionItem     // Item inside an ItemCollection (Set)
        case vaultPage          // Page directly inside a PageType (root)
        case vaultCollection    // PageCollection inside a PageType
        case setItem            // alias for collectionItem in PageCollectionDetailView context
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pommoraDetailRow)
    }
}

extension UTType {
    /// Custom UTType for in-process drag of detail-pane rows. Conforming
    /// to `data` keeps it private to Pommora (not exposed to other apps).
    /// `nonisolated` is REQUIRED: the project builds under default-MainActor
    /// isolation, so a bare `static let` here is inferred MainActor-isolated
    /// and the `nonisolated` Transferable conformance (`transferRepresentation`)
    /// can't reference it. Because `UTType` is `Sendable`, plain `nonisolated`
    /// (no `unsafe`) is the correct, warning-free form.
    nonisolated static let pommoraDetailRow = UTType(exportedAs: "com.pommora.detail-row")
}
