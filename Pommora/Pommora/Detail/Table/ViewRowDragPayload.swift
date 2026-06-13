import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The GALLERY's per-card drag currency — the `Transferable` carried by each
/// gallery card's `.draggable` and read back by its `.dropDestination`. Holds
/// just the dragged pages' ULIDs; `GroupDropPlanner` resolves the actual
/// move/reorder/rewrite from the drop target, so no source-zone metadata crosses
/// the drag boundary (ID-only keeps the payload `Sendable` with no view types
/// leaking through). The wrapped outline table does NOT use this Transferable —
/// it drags via its own AppKit pasteboard type (`ViewOutlineTable.rowDragType` =
/// `com.pommora.view-row`) and reads the ids straight off the pasteboard.
///
/// Encoded as `public.json` (gallery path only): a custom `UTType(exportedAs:)`
/// would only match if declared in the app's `UTExportedTypeDeclarations`, which
/// this app's generated Info.plist lacks — an unregistered private type silently
/// fails `dropDestination(for:)`. `.json` is system-registered and always matches.
struct ViewRowDragPayload: Codable, Equatable, Hashable, Sendable, Transferable {
    let pageIDs: [String]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
