// RecentsManager.swift
import Foundation
import Observation

@MainActor
@Observable
final class RecentsManager {
    static let storeCap = 500
    static let dropdownCap = 100

    private(set) var entries: [EntityStateRef] = []
    private(set) var cursor: Int = 0
    var pendingError: (any Error)?

    /// When true, sidebar-selection observers should NOT call `record(...)`.
    /// Routing layer sets this around programmatic selection changes
    /// (e.g., back/forward stepping) so the manager doesn't double-record.
    var isNavigatingHistory: Bool = false

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    /// Top of the store, capped for dropdown rendering. Storage containers
    /// (Vault / Collection / Type / Set) participate in the back/forward stack
    /// and persist in `entries`, but are hidden here: the dropdown is a
    /// quick-jump list for content leaves (Pages), while containers are reached
    /// via the sidebar. One structure, two projections.
    var dropdownTop: [EntityStateRef] {
        Array(
            entries.lazy
                .filter { ref in
                    guard let kind = ref.typedKind else { return false }
                    return !Self.containerKinds.contains(kind)
                }
                .prefix(Self.dropdownCap)
        )
    }

    var canStepBack: Bool { cursor < entries.count - 1 }
    var canStepForward: Bool { cursor > 0 }

    func load() async {
        let url = NexusPaths.nexusStateURL(in: nexus)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            let state = try AtomicJSON.decode(NexusState.self, from: url)
            // Drop entries whose kind is no longer steppable: Contexts (Spaces /
            // Topics / Projects) and Items/Agenda. Pages + storage containers
            // (Vault / Collection / Type / Set) are kept — the latter were
            // excluded before this build, so old state.json files self-heal.
            let filtered = state.recents.filter { ref in
                guard let kind = ref.typedKind else { return false }
                return Self.recordableKinds.contains(kind)
            }
            self.entries = filtered
            self.cursor = min(state.cursor, max(0, filtered.count - 1))
            if filtered.count != state.recents.count {
                Task { try? await save() }
            }
        } catch {
            self.pendingError = error
        }
    }

    /// Kinds that enter the shared `entries` list — i.e. what the Back/Forward
    /// stack steps through and what persists to state.json. Pages plus the four
    /// storage containers (Vault / Collection / Type / Set). Items are omitted:
    /// they open in a popover Item Window, not the main pane, so stepping
    /// "back" to one doesn't fit the navigation flow. Contexts (Spaces /
    /// Topics / Projects) stay out too — they're reached via the sidebar.
    static let recordableKinds: Set<EntityStateRef.Kind> = [
        .page, .vault, .collection, .itemType, .set,
    ]

    /// Storage containers recorded into `entries` (steppable) but hidden from
    /// the Recents dropdown projection (see `dropdownTop`).
    static let containerKinds: Set<EntityStateRef.Kind> = [
        .vault, .collection, .itemType, .set,
    ]

    func record(_ ref: EntityStateRef) {
        guard let kind = ref.typedKind, Self.recordableKinds.contains(kind) else { return }
        entries.removeAll { $0 == ref }
        entries.insert(ref, at: 0)
        if entries.count > Self.storeCap {
            entries.removeLast(entries.count - Self.storeCap)
        }
        cursor = 0
        Task { try? await save() }
    }

    @discardableResult
    func stepBack() -> EntityStateRef? {
        guard canStepBack else { return nil }
        cursor += 1
        Task { try? await save() }
        return entries[cursor]
    }

    @discardableResult
    func stepForward() -> EntityStateRef? {
        guard canStepForward else { return nil }
        cursor -= 1
        Task { try? await save() }
        return entries[cursor]
    }

    func save() async throws {
        let url = NexusPaths.nexusStateURL(in: nexus)
        try FileManager.default.createDirectory(
            at: NexusPaths.nexusConfigDir(in: nexus),
            withIntermediateDirectories: true
        )
        // Read-modify-write the shared file (pinned entries managed separately).
        var state: NexusState
        if FileManager.default.fileExists(atPath: url.path) {
            state = (try? AtomicJSON.decode(NexusState.self, from: url)) ?? NexusState()
        } else {
            state = NexusState()
        }
        state.recents = entries
        state.cursor = cursor
        do {
            try AtomicJSON.write(state, to: url)
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
