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
