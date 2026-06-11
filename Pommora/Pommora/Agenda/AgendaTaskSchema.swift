import Foundation

/// `_taskconfig.json` for the Tasks singleton folder (default
/// `<nexus>/Tasks/`; folder is renameable per Settings). Defines built-in
/// `_status` Status property + user-defined additions + saved views.
///
/// As of Phase G.1 the schema starts with exactly one built-in property:
/// `_status` (Status type, `PropertyDefinition.StatusGroup.defaultSeed()`).
/// The legacy `_type` Select property has been retired from the default seed.
struct AgendaTaskSchema: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var properties: [PropertyDefinition]
    var views: [SavedView]  // saved view configurations
    var modifiedAt: Date
    /// Persisted default sort for the Tasks list view. Nil → callers fall back
    /// to `DefaultSortConfig.legacyDefault` (`_modified_at desc`). Phase J
    /// wires this to column-header sort persistence.
    var defaultSort: DefaultSortConfig?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, icon, properties, views
        case modifiedAt = "modified_at"
        case defaultSort = "default_sort"
    }

    // MARK: - Custom Codable (legacy migration)

    /// Legacy `_taskconfig.json` shapes (pre-v0.3.0) stored a nested `Property`
    /// struct with `name`, `type`, `options`, `builtin`, and `default` but no `id`
    /// field. On first decode, this path transforms the old shape into
    /// `[PropertyDefinition]` by minting stable IDs:
    /// - builtin `true` → `"_" + name` (so `"type"` becomes `"_type"`)
    /// - builtin `false` → `ReservedPropertyID.mintUserPropertyID()` (`prop_<ulid>`)
    ///
    /// The transformed schema is re-saved by `AgendaTaskManager.loadAll()` on first
    /// launch, so subsequent decodes always hit the `PropertyDefinition` path.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.views = try c.decodeIfPresent([SavedView].self, forKey: .views) ?? []
        self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        self.defaultSort = try c.decodeIfPresent(DefaultSortConfig.self, forKey: .defaultSort)

        // Attempt legacy decode first: if the raw JSON has `builtin` fields (old shape),
        // `LegacyProperty` decoding succeeds and we migrate to `[PropertyDefinition]`.
        // If `LegacyProperty` decode fails (because `builtin` is absent — new shape),
        // fall through to `[PropertyDefinition]` decode.
        //
        // Discrimination: `LegacyProperty` requires `builtin: Bool`; `PropertyDefinition`
        // does not carry that field. Decoding a new-shape array as `[LegacyProperty]`
        // fails because `builtin` is missing. Decoding an old-shape array as
        // `[PropertyDefinition]` succeeds but yields `id == ""` for every entry —
        // we use `builtin`-presence as the clean discriminator via the LegacyProperty path.
        let rawProperties: [PropertyDefinition]
        if let legacyProps = try? c.decode([LegacyProperty].self, forKey: .properties) {
            rawProperties = legacyProps.map { legacy in
                PropertyDefinition(
                    id: legacy.builtin ? "_\(legacy.name)" : ReservedPropertyID.mintUserPropertyID(),
                    name: legacy.name,
                    type: legacy.type,
                    selectOptions: legacy.options
                )
            }
        } else {
            rawProperties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        }
        self.properties = rawProperties.droppingUserRelations()
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(properties, forKey: .properties)
        try c.encode(views, forKey: .views)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(defaultSort, forKey: .defaultSort)
    }

    // MARK: - Default seed

    static func defaultSeed() -> AgendaTaskSchema {
        AgendaTaskSchema(
            schemaVersion: 1,
            icon: "checkmark.circle",
            properties: [
                PropertyDefinition(
                    id: "_status",
                    name: "Status",
                    type: .status,
                    statusGroups: PropertyDefinition.StatusGroup.defaultSeed()
                )
            ],
            views: [],
            modifiedAt: Date()
        )
    }

    // MARK: - Private memberwise init (for defaultSeed)

    private init(
        schemaVersion: Int,
        icon: String?,
        properties: [PropertyDefinition],
        views: [SavedView],
        modifiedAt: Date,
        defaultSort: DefaultSortConfig? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.icon = icon
        self.properties = properties
        self.views = views
        self.modifiedAt = modifiedAt
        self.defaultSort = defaultSort
    }
}

// MARK: - Resolved properties

extension AgendaTaskSchema {
    /// Stored `properties` plus the three pre-configured tier relation properties
    /// (Areas/Topics/Projects), merged via BuiltInContextLinkProperties. Surfaces that
    /// must SHOW tiers read this; everything that persists or mutates the schema
    /// keeps using the stored `properties`.
    func resolvedProperties(tierConfig: TierConfig) -> [PropertyDefinition] {
        BuiltInContextLinkProperties.merge(
            existing: properties,
            tierConfig: tierConfig,
            sourceTypeID: ReservedTypeID.agendaTasks
        )
    }
}

// MARK: - Legacy decode helper

/// Mirrors the pre-v0.3.0 nested `Property` shape stored in `_taskconfig.json`.
/// Used only by `AgendaTaskSchema.init(from:)` for legacy migration; deleted from
/// the on-disk format after first re-save.
private struct LegacyProperty: Codable {
    var name: String
    var type: PropertyType
    var options: [PropertyDefinition.SelectOption]?
    var builtin: Bool
    var defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case name, type, options, builtin
        case defaultValue = "default"
    }
}
