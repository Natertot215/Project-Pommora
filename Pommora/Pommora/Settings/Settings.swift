import Foundation

/// Per-Nexus user preferences. On disk at `<nexus>/.nexus/settings.json`.
/// Loaded by SettingsManager; consumed by every UI label-rendering site.
///
/// Existing `tier-config.json` and `saved-config.json` stay separate for v0.3.0
/// (consolidation deferred to v0.6.0 Settings UI work).
///
/// ## Auto-migration
/// `defaultsVersion` tracks which set of default values was seeded.  On every
/// `loadOrSeed`, `Settings.migrate(_:)` runs when `defaultsVersion <
/// currentDefaultsVersion`, overwriting only fields whose on-disk value still
/// equals the OLD default for that version.  User-customized fields (whose value
/// differs from the version-era default) are always preserved.
struct Settings: Codable, Equatable, Hashable, Sendable {
    /// Schema version — bumped when the on-disk shape changes (field renames,
    /// additions, removals).  Separate from `defaultsVersion`.
    var version: Int
    /// Which set of built-in defaults was last seeded.  When this is less than
    /// `currentDefaultsVersion`, `migrate(_:)` runs on load.  Missing from
    /// old files; decoded as 0 via `defaultValue` in the custom init.
    var defaultsVersion: Int
    var accentColor: SettingsAccentColor?
    var labels: SettingsLabels
    /// Per-Nexus toggle: show a page's icon (and the "Add icon" affordance) in
    /// the page header beside the title. Default OFF — opt-in per Nexus. Wired
    /// here ahead of the v0.6.0 Settings editor so the future toggle row binds
    /// to an existing field rather than triggering a migration.
    var showPageIcon: Bool
    var modifiedAt: Date

    // MARK: - Versioning constants

    /// The defaults version shipped with the current build.  Increment this
    /// whenever a default value changes and add a migration step in `migrate(_:)`.
    static let currentDefaultsVersion: Int = 3

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version
        case defaultsVersion = "defaults_version"
        case accentColor = "accent_color"
        case labels
        case showPageIcon = "show_page_icon"
        case modifiedAt = "modified_at"
    }

    init(
        version: Int,
        defaultsVersion: Int = Self.currentDefaultsVersion,
        accentColor: SettingsAccentColor? = nil,
        labels: SettingsLabels,
        showPageIcon: Bool = false,
        modifiedAt: Date
    ) {
        self.version = version
        self.defaultsVersion = defaultsVersion
        self.accentColor = accentColor
        self.labels = labels
        self.showPageIcon = showPageIcon
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        // Old files lack "defaults_version" → treat as 0 (stale; needs migration).
        defaultsVersion = (try? c.decode(Int.self, forKey: .defaultsVersion)) ?? 0
        accentColor = try c.decodeIfPresent(SettingsAccentColor.self, forKey: .accentColor)
        labels = try c.decode(SettingsLabels.self, forKey: .labels)
        // Old files lack "show_page_icon" → default OFF (matches the new default,
        // so migration has nothing to rewrite — see migrate(_:) v2→v3).
        showPageIcon = (try? c.decode(Bool.self, forKey: .showPageIcon)) ?? false
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }

    // MARK: - Default seed

    static func defaultSeed() -> Settings {
        Settings(
            version: 1,
            defaultsVersion: currentDefaultsVersion,
            accentColor: nil,  // nil = system default
            labels: SettingsLabels.defaults(),
            showPageIcon: false,  // opt-in per Nexus
            modifiedAt: Date()
        )
    }

    // MARK: - Auto-migration

    /// Migrates `old` from its `defaultsVersion` up to `currentDefaultsVersion`.
    ///
    /// Each version step overwrites fields that still carry the OLD default value
    /// with the NEW default value, while preserving user-customized fields.
    ///
    /// Returns the (possibly updated) Settings.  Returns `old` unchanged when
    /// `old.defaultsVersion == currentDefaultsVersion` (no-op fast path).
    static func migrate(_ old: Settings) -> Settings {
        guard old.defaultsVersion < currentDefaultsVersion else { return old }

        var s = old

        // v0 → v1: first defaults version.  No field-rename steps yet —
        // this is the structural scaffold.  Future releases add per-field
        // comparisons here, e.g.:
        //
        //   if s.labels.sidebarSections.pages == "<old default>" {
        //       s.labels.sidebarSections.pages = "<new default>"
        //   }
        //
        // Only fields whose on-disk value still equals the OLD default are
        // overwritten; any field the user customized (different from OLD default)
        // is left as-is.
        if s.defaultsVersion < 1 {
            // No stale-default rewrites for v0→v1; just bump the version.
            s.defaultsVersion = 1
        }

        if s.defaultsVersion < 2 {
            // v1→v2: Items sidebar section header renamed from "Types" → "Items"
            // per Nathan's 2026-05-25 directive. Only overwrite if the user is
            // still on the old default (preserves any custom rename).
            if s.labels.sidebarSections.items == "Types" {
                s.labels.sidebarSections.items = "Items"
            }
            s.defaultsVersion = 2
        }

        if s.defaultsVersion < 3 {
            // v2→v3: added `showPageIcon` (page-header icon toggle). Brand-new
            // field — absent in older files, decoded as `false`, which already
            // equals the new default, so there's nothing to rewrite. Just
            // record the version.
            s.defaultsVersion = 3
        }

        // Clamp to current in case intermediate versions were skipped.
        s.defaultsVersion = currentDefaultsVersion
        return s
    }
}

enum SettingsAccentColor: String, Codable, CaseIterable, Hashable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray
}
