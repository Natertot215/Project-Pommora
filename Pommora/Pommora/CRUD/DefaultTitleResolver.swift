import Foundation

/// Generates a guaranteed-unique default title for a stubbed entity in the
/// system-wide stub-and-inline-rename CRUD flow (paradigm decision: every
/// "New X" trigger creates immediately with a default title, then auto-flips
/// the row into inline-rename mode — no modal sheets).
///
/// Format: `"New <Label>"`, then `"New <Label> 2"`, `"New <Label> 3"`, etc.
/// Picks the lowest-numbered free slot — if the bare default is unused, it
/// wins even when higher-numbered duplicates exist (e.g. `"New Folder 2"`
/// alone yields `"New Folder"`, not `"New Folder 3"`).
///
/// The output is intentionally guaranteed-unique against `existingTitles`,
/// so the caller's validator's duplicate-title check passes by construction
/// when the stub is inserted. Validators still run at the commit-from-rename
/// step when the user types the real name.
enum DefaultTitleResolver {

    /// Returns a unique default title of the form `"New <label>"` (or
    /// `"New <label> N"` with the smallest free integer N ≥ 2 when the bare
    /// default collides).
    ///
    /// - Parameters:
    ///   - label: The entity-kind label (singular). Pulled from `SettingsLabels`
    ///     by callers — e.g. `"Folder"`, `"Collection"`, `"Page"`, `"Vault"`.
    ///   - existingTitles: The current sibling titles to avoid colliding with.
    ///     Order doesn't matter; comparison is case-sensitive (matches the
    ///     validators' exact-title uniqueness rules).
    static func resolve(label: String, existingTitles: [String]) -> String {
        let bare = "New \(label)"
        let taken = Set(existingTitles)
        guard taken.contains(bare) else { return bare }
        var n = 2
        while taken.contains("\(bare) \(n)") {
            n += 1
        }
        return "\(bare) \(n)"
    }
}
