import Foundation

/// Single registry of the current on-disk schema version per nexus entity.
/// Bump the value here when an entity's sidecar JSON shape changes; entities
/// default their `schemaVersion` to these. (App-level state files — AppState,
/// NexusState, NexusIdentity — version separately and are intentionally not here.)
enum SchemaVersion {
    static let pageType = 2
    static let pageCollection = 1
    static let pageSet = 1
    static let tierConfig = 1
    static let homepage = 1
    static let savedConfig = 1
    static let agendaTask = 1
    static let agendaEvent = 1
}
