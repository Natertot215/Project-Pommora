import Foundation

/// Finder-duplicating a container folder clones its sidecar ULID. On load,
/// the FIRST folder discovered keeps the id; every later duplicate mints a
/// fresh ULID (via `reID`) and re-saves its sidecar. Index rows re-derive on
/// rebuild, and child FK drift (a Set pointing at its Collection's old id,
/// etc.) is re-pointed by the existing heal-on-load passes.
///
/// `seen` is threaded `inout` so a caller healing several sibling groups
/// (e.g. PageTypeManager healing each Type's Collections) shares ONE id
/// namespace across the whole load — a duplicated TYPE folder clones every
/// nested Collection id across two Types, and only a load-wide set catches
/// that.
///
/// Best-effort + idempotent: a failed sidecar re-save is swallowed (the
/// filesystem stays canonical and the next load re-heals); the returned array
/// always carries distinct ids in discovery order.
@MainActor
enum ContainerIDHealer {
    static func heal<T: Identifiable>(
        _ items: [T],
        seen: inout Set<String>,
        reID: (inout T) -> Void,
        save: (T) throws -> Void
    ) -> [T] where T.ID == String {
        var healed: [T] = []
        healed.reserveCapacity(items.count)
        for var item in items {
            if !seen.insert(item.id).inserted {
                reID(&item)
                seen.insert(item.id)
                try? save(item)
            }
            healed.append(item)
        }
        return healed
    }
}
