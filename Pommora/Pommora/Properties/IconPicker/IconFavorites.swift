import Foundation

/// App-level **Saved** icons for `IconPicker` — a small, ordered, deduped list
/// of SF Symbol names the user has pinned for quick reuse.
///
/// The ordering/cap/dedupe behaviour is **pure** (`toggled`) so it is unit-tested
/// independently of where the list is stored. Persistence is a thin UserDefaults
/// layer (`load` / `persist`).
///
/// **Storage note:** kept in app-level `UserDefaults`, NOT the nexus file model.
/// This is a transient picker convenience (the picker works fully without it),
/// not portable user content — so it deliberately stays out of `.nexus/`. If it
/// should later sync per-nexus (e.g. into `settings.json`), only `load`/`persist`
/// change; `toggled` is storage-agnostic.
enum IconFavorites {
    /// UserDefaults key holding the JSON-encoded `[String]` of saved symbols.
    static let defaultsKey = "pommora.iconPicker.saved"

    /// Upper bound on the Saved list — newest-first, oldest dropped past this.
    static let cap = 60

    /// Pure toggle: if `name` is already saved, remove it; otherwise prepend it
    /// (newest-first), deduped and capped to `cap`.
    static func toggled(_ name: String, in saved: [String]) -> [String] {
        if saved.contains(name) {
            return saved.filter { $0 != name }
        }
        return Array(([name] + saved).prefix(cap))
    }

    /// Load the saved list (empty if unset / undecodable).
    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: defaultsKey),
            let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    /// Persist the saved list as JSON.
    static func persist(_ saved: [String], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
