import Foundation

/// Lightweight cross-entity lookup value passed to validators that need to
/// resolve IDs to other entities (e.g. SubtopicValidator checking parent Topic
/// existence). Avoids a heavyweight coordinator class — each manager fills
/// only the closures it needs.
///
/// All closures return `nil` if the ID is unknown.
struct NexusContext: Sendable {
    var lookupSpace: @Sendable (String) -> Space?
    var lookupTopic: @Sendable (String) -> Topic?
    var lookupSubtopic: @Sendable (String) -> Subtopic?
    var lookupVault: @Sendable (String) -> PageType?

    /// Sentinel context with all lookups returning nil — for tests / standalone validation.
    static let empty = NexusContext(
        lookupSpace: { _ in nil },
        lookupTopic: { _ in nil },
        lookupSubtopic: { _ in nil },
        lookupVault: { _ in nil }
    )
}
