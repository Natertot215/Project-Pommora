import Foundation

/// Property type catalog for Vault schemas. Shared across Pages and Agenda.
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

    /// Whether a column of this type offers a meaningful ordering in the Sort
    /// pane. Relations (ID pointers) and file attachments have no natural sort.
    var isSortable: Bool {
        switch self {
        case .number, .checkbox, .date, .datetime, .select, .multiSelect,
            .status, .url, .lastEditedTime:
            return true
        case .relation, .file:
            return false
        }
    }
}
