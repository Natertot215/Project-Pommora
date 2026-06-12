import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Carried during a custom-table row drag. Holds just the dragged
/// pages' ULIDs — `GroupDropPlanner` resolves the actual move/reorder/rewrite
/// from the drop target, so no source-zone metadata crosses the drag boundary
/// (ID-only keeps the payload `Sendable` with no view types leaking through).
///
/// Encoded as `public.json`: a
/// custom `UTType(exportedAs:)` would only match if declared in the app's
/// `UTExportedTypeDeclarations`, which this app's generated Info.plist lacks —
/// an unregistered private type silently fails `dropDestination(for:)`. `.json`
/// is system-registered and always matches.
struct ViewRowDragPayload: Codable, Equatable, Hashable, Sendable, Transferable {
    let pageIDs: [String]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
