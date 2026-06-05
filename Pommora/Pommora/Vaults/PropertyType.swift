import Foundation

/// Property type catalog for Vault schemas. Shared across Pages, Items, Agenda.
/// Stored on disk as raw lowercase string.
enum PropertyType: String, Codable, CaseIterable, Hashable, Sendable {
    case number
    case checkbox
    case date  // calendar date only
    case datetime  // date + time + timezone
    case select  // single choice from options
    case multiSelect = "multi_select"
    case status  // single choice with workflow semantics
    case url
    case relation  // points to another entity by ID; tier-only tolerance; retired from user creation
    case lastEditedTime = "last_edited_time"  // auto-managed timestamp
    case file  // file attachment(s)
}
