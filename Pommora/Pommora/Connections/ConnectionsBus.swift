import Foundation

/// App-owned signal that the set of resolvable connection titles changed —
/// an entity was created, renamed, or deleted in SOME surface/window. Open Page
/// editors observe it through the `MarkdownPMBus.connectionsChanged` slot (wired
/// in `MarkdownEditorConfig.pommora`) and re-style: every `[[ ]]`/`{{ }}` re-runs
/// its resolver, so a phantom whose target just appeared lights up live — without
/// the user typing in the doc holding the link.
///
/// One stable, app-owned name (NOT a per-instance/ad-hoc name): the editor
/// coordinator's `subscribeToBusNotifications(replacing:)` removes-then-re-adds on
/// every config swap, so a config change never double-registers this observer.
/// This mirrors the proven `appearanceDidChangeNotification` conduit — a host-
/// supplied `Notification.Name` the MarkdownPM engine observes and restyles on.
enum ConnectionsBus {
    /// The signal name. Set on `MarkdownPMBus.connectionsChanged` and posted by
    /// the CRUD managers after their connection-index work runs. `nonisolated` —
    /// a `Notification.Name` constant has no actor affinity, and the editor's
    /// `nonisolated` bus observer needs to reference it (the app target builds
    /// `-default-isolation=MainActor`, which would otherwise infer it `@MainActor`).
    nonisolated static let changed = Notification.Name("PommoraConnectionsChanged")

    /// Post the change signal. `@MainActor` because the editor coordinator's bus
    /// observers use `@objc` selector dispatch (no `queue: .main`), so handlers
    /// run on the posting thread — and the restyle they trigger touches TextKit,
    /// which must be on main. The CRUD managers are already `@MainActor`.
    ///
    /// `object` carries the posting manager so a scoped observer can filter to one
    /// source (tests do this to stay attributable). The editor observes with
    /// `object: nil`, which matches regardless — it wants EVERY change, from any
    /// surface — so production behavior is unchanged whether `object` is set.
    @MainActor
    static func postChanged(from object: AnyObject? = nil) {
        NotificationCenter.default.post(name: changed, object: object)
    }
}
