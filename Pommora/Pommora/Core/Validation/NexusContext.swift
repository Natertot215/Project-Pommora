import Foundation

/// Lightweight cross-entity lookup value passed to validators that need to
/// resolve IDs to other entities (e.g. ProjectValidator checking parent Topic
/// existence, PropertyDefinitionValidator resolving a relation target Type).
/// Avoids a heavyweight coordinator class — each manager fills only the
/// closures it needs.
///
/// All closures return `nil` if the ID is unknown.
struct NexusContext: Sendable {
    var lookupArea: @Sendable (String) -> Area?
    var lookupTopic: @Sendable (String) -> Topic?
    var lookupProject: @Sendable (String) -> Project?
    var lookupVault: @Sendable (String) -> PageType?

    /// Sentinel context with all lookups returning nil — for tests / standalone validation.
    static let empty = NexusContext(
        lookupArea: { _ in nil },
        lookupTopic: { _ in nil },
        lookupProject: { _ in nil },
        lookupVault: { _ in nil }
    )

    /// Builds a context that resolves PageType targets from disk via the
    /// `PageType.find` flat-layout scan. Used by the Type / schema managers
    /// (PageTypeManager / Agenda{Task,Event}Manager) when validating a relation
    /// property's target — those managers hold only a `Nexus`, not a
    /// peer-manager snapshot, and the on-disk scan resolves targets living
    /// outside the calling manager's in-memory `types`. Captures only the Sendable
    /// `id` / `rootURL` (Nexus itself is non-Sendable) and rebuilds a `Nexus` inside
    /// the `@Sendable` closure. Area / Topic / Project lookups stay nil — relation
    /// validation only needs the Type catalog.
    @MainActor
    static func forTypeResolution(in nexus: Nexus) -> NexusContext {
        let id = nexus.id
        let rootURL = nexus.rootURL
        return NexusContext(
            lookupArea: { _ in nil },
            lookupTopic: { _ in nil },
            lookupProject: { _ in nil },
            // `find` is @MainActor (project-default isolation); this @Sendable
            // closure is invoked only synchronously from the @MainActor schema
            // managers that call PropertyDefinitionValidator, so asserting main-actor
            // isolation is sound and keeps `find` the single resolution path.
            lookupVault: { typeID in
                MainActor.assumeIsolated {
                    PageType.find(id: typeID, in: Nexus(id: id, rootURL: rootURL))
                }
            }
        )
    }
}
