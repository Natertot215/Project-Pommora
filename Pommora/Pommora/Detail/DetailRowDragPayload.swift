import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Carried during a Page Collection / Item Set detail-view row drag. Just the dragged row's
/// ULID — the offset-based drop handler resolves position via `DetailReorderPlanner`
/// (driving `reorderPages(in:)` / `reorderItems(in:)`), so no source/zone metadata
/// is needed.
///
/// Encoded as `public.json`, a **system-registered** content type. A custom
/// `UTType(exportedAs:)` would only register if declared in the app's
/// `UTExportedTypeDeclarations`; this app ships a generated Info.plist with no
/// such entry, so an unregistered private type never lands on the pasteboard
/// type graph and `dropDestination(for:)` silently fails to match it (the drag
/// lifts but no drop ever fires). `.json` sidesteps that entirely.
struct DetailRowDragPayload: Codable, Equatable, Hashable, Sendable, Transferable {
    let rowID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
