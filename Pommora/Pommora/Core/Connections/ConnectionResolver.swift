import Foundation
import MarkdownPM
import SwiftUI

/// Title-keyed WikiLinkResolver backed by the SQLite index. Resolves SYNCHRONOUSLY
/// (the styler calls `resolve` sync, inside the TextKit layout pass — it cannot await
/// the async index query path). Drives `[[ ]]` — pages are the only link target.
/// A resolved id is returned for in-memory metadata only — LD-28 keeps it off disk.
struct PommoraConnectionResolver: WikiLinkResolver {
    let index: PommoraIndex

    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        guard let entity = IndexQuery(index).resolveUniqueEntity(displayName) else { return nil }
        return WikiLinkResolution(id: entity.id, exists: true, icon: entity.icon)
    }
}

extension EnvironmentValues {
    /// The stable `[[ ]]` connection resolver injected by `NexusEnvironment`.
    /// A protocol existential, so it rides through `@Entry` (not `.environment(object)`)
    /// — defaults to NoOp so previews + any subtree without a live Nexus stay inert.
    @Entry var connectionResolver: any WikiLinkResolver = NoOpWikiLinkResolver()
}
