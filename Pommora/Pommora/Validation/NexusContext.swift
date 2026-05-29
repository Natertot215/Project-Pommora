import Foundation

/// Lightweight cross-entity lookup value passed to validators that need to
/// resolve IDs to other entities (e.g. ProjectValidator checking parent Topic
/// existence, PropertyDefinitionValidator resolving a relation target Type).
/// Avoids a heavyweight coordinator class — each manager fills only the
/// closures it needs.
///
/// All closures return `nil` if the ID is unknown.
struct NexusContext: Sendable {
    var lookupSpace: @Sendable (String) -> Space?
    var lookupTopic: @Sendable (String) -> Topic?
    var lookupProject: @Sendable (String) -> Project?
    var lookupVault: @Sendable (String) -> PageType?
    /// Resolve an Item Type by ID. Defaulted to a nil-returning closure so the
    /// many existing construction sites that don't supply it keep compiling;
    /// relation-target validation (PropertyDefinitionValidator) fills it.
    var lookupItemType: @Sendable (String) -> ItemType? = { _ in nil }

    /// Sentinel context with all lookups returning nil — for tests / standalone validation.
    static let empty = NexusContext(
        lookupSpace: { _ in nil },
        lookupTopic: { _ in nil },
        lookupProject: { _ in nil },
        lookupVault: { _ in nil }
    )

    /// Builds a context that resolves PageType / ItemType targets from disk via the
    /// `PageType.find` / `ItemType.find` flat-layout scans. Used by the Type / schema
    /// managers (PageTypeManager / ItemTypeManager / Agenda{Task,Event}Manager) when
    /// validating a relation property's target — those managers hold only a `Nexus`,
    /// not a peer-manager snapshot, and the on-disk scan resolves targets living
    /// outside the calling manager's in-memory `types`. Captures only the Sendable
    /// `id` / `rootURL` (Nexus itself is non-Sendable) and rebuilds a `Nexus` inside
    /// each `@Sendable` closure. Space / Topic / Project lookups stay nil — relation
    /// validation only needs the two Type catalogs.
    @MainActor
    static func forTypeResolution(in nexus: Nexus) -> NexusContext {
        let id = nexus.id
        let rootURL = nexus.rootURL
        return NexusContext(
            lookupSpace: { _ in nil },
            lookupTopic: { _ in nil },
            lookupProject: { _ in nil },
            // `find` is @MainActor (project-default isolation); these @Sendable
            // closures are invoked only synchronously from the @MainActor schema
            // managers that call PropertyDefinitionValidator, so asserting main-actor
            // isolation is sound and keeps `find` the single resolution path.
            lookupVault: { typeID in
                MainActor.assumeIsolated {
                    PageType.find(id: typeID, in: Nexus(id: id, rootURL: rootURL))
                }
            },
            lookupItemType: { typeID in
                MainActor.assumeIsolated {
                    ItemType.find(id: typeID, in: Nexus(id: id, rootURL: rootURL))
                }
            }
        )
    }
}
