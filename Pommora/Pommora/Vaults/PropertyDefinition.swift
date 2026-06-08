import Foundation

/// One property schema entry inside a PageType / ItemType / Tasks / Events
/// per-kind sidecar (`_pagetype.json` / `_itemtype.json` / `_taskconfig.json`
/// / `_eventconfig.json`). Type-specific config fields live as optionals on
/// this struct; only the ones relevant to `type` should be populated.
///
/// Identity is the stored `id` field — a stable ULID minted at creation via
/// `ReservedPropertyID.mintUserPropertyID()` (user-defined: `prop_<ulid>`) or
/// the reserved-catalog form (`_status`, `_tier1`, …). The `name` field is
/// the renameable display label; renames are schema-only writes (member
/// files keyed by `id` are untouched). Legacy decode (pre-v0.3.0 schemas
/// lacking the `id` field) synthesises `id = ""` — the adoption-scan
/// migration backfills with a freshly-minted ULID before re-saving.
struct PropertyDefinition: Codable, Equatable, Identifiable, Hashable, Sendable {
    /// Stable ULID. Empty string signals "legacy schema, needs migration".
    var id: String
    /// User-facing display label. Renameable; schema-only writes.
    var name: String
    var type: PropertyType

    // Type-specific config (all optional, only populated when relevant to `type`):
    var icon: String?  // optional SF Symbol per-property (contextual rendering — see L10)
    var numberFormat: NumberFormat?  // number
    var dateIncludesTime: Bool?  // date — irrelevant for `datetime` type
    var selectOptions: [SelectOption]?  // select + multiSelect
    var statusGroups: [StatusGroup]?  // status — 3 fixed groups; see StatusGroup.defaultSeed()
    var relationTarget: RelationTarget?  // relation
    /// Reverse-side display name override. v1 semantics: populated only on tier
    /// property entries (_tier1/_tier2/_tier3) where the target is a Context.
    /// User-created relations leave this nil.
    var reverseName: String? = nil
    /// Reverse-side icon override. Same semantics as reverseName.
    var reverseIcon: String? = nil
    var accept: [String]?  // file — MIME-type whitelist (e.g. ["application/pdf", "image/*"])
    var displayAs: DisplayVariant?  // status — render variant (nil = .box default)
    var dateFormat: DateFormat?  // date — date-portion display format (nil = .full default)
    var timeFormat: TimeFormat?  // date — time-portion display (nil = .none, date only)

    init(
        id: String,
        name: String,
        type: PropertyType,
        icon: String? = nil,
        numberFormat: NumberFormat? = nil,
        dateIncludesTime: Bool? = nil,
        selectOptions: [SelectOption]? = nil,
        statusGroups: [StatusGroup]? = nil,
        relationTarget: RelationTarget? = nil,
        reverseName: String? = nil,
        reverseIcon: String? = nil,
        accept: [String]? = nil,
        displayAs: DisplayVariant? = nil,
        dateFormat: DateFormat? = nil,
        timeFormat: TimeFormat? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.numberFormat = numberFormat
        self.dateIncludesTime = dateIncludesTime
        self.selectOptions = selectOptions
        self.statusGroups = statusGroups
        self.relationTarget = relationTarget
        self.reverseName = reverseName
        self.reverseIcon = reverseIcon
        self.accept = accept
        self.displayAs = displayAs
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
    }

    // MARK: - Display

    /// Single icon source: the per-property custom SF Symbol if set, else the
    /// type's picker icon. Call sites must use this instead of inlining
    /// `icon ?? type.pickerIcon` (DRY — one source of truth).
    var displayIcon: String { icon ?? type.pickerIcon }

    // MARK: - Nested types

    struct SelectOption: Codable, Equatable, Hashable, Identifiable, Sendable {
        var value: String  // canonical key (immutable post-create)
        var label: String  // user-facing
        var color: SelectColor?

        var id: String { value }
    }

    enum SelectColor: String, Codable, CaseIterable, Hashable, Sendable {
        case gray, brown, orange, yellow, green, blue, purple, pink, red, teal, indigo
    }

    enum NumberFormat: String, Codable, CaseIterable, Hashable, Sendable {
        case integer, decimal, percent, currency
    }

    /// Status group discriminator. Three fixed slots — adding a fourth breaks EventKit
    /// sync semantics (no clean mapping target for a `cancelled` group); customisation
    /// happens by adding options within groups, never adding groups.
    enum StatusGroupID: String, Codable, CaseIterable, Hashable, Sendable {
        case upcoming
        case inProgress = "in_progress"
        case done
    }

    struct StatusOption: Codable, Equatable, Hashable, Identifiable, Sendable {
        var value: String  // canonical key, immutable post-create
        var label: String  // renameable display
        var color: SelectColor?  // nil inherits group default
        var groupID: StatusGroupID

        var id: String { value }

        enum CodingKeys: String, CodingKey {
            case value, label, color
            case groupID = "group_id"
        }
    }

    struct StatusGroup: Codable, Equatable, Hashable, Identifiable, Sendable {
        var id: StatusGroupID
        var label: String  // user-renameable (per Properties.md)
        var color: SelectColor  // default for options that don't override
        var options: [StatusOption]

        /// Default seed when a Status property is first added (Pages/Items) or when
        /// AgendaTaskSchema/AgendaEventSchema bootstraps. Matches Properties.md
        /// § "Status property type" → "Default seed".
        static func defaultSeed() -> [StatusGroup] {
            [
                StatusGroup(
                    id: .upcoming,
                    label: "Upcoming",
                    color: .gray,
                    options: [
                        StatusOption(value: "not_started", label: "Not started", color: nil, groupID: .upcoming)
                    ]
                ),
                StatusGroup(
                    id: .inProgress,
                    label: "In Progress",
                    color: .blue,
                    options: [
                        StatusOption(
                            value: "in_progress", label: "In progress", color: .blue, groupID: .inProgress
                        )
                    ]
                ),
                StatusGroup(
                    id: .done,
                    label: "Done",
                    color: .green,
                    options: [
                        StatusOption(value: "done", label: "Done", color: .green, groupID: .done)
                    ]
                ),
            ]
        }
    }

    /// Picker constraint for a Relation property. Tier-only post-Relations-redesign.
    ///
    /// On-disk shape is a tagged object: `{"kind": "context_tier", "tier": N}`.
    /// Retired user cases (page_type / item_type / page_collection / item_collection /
    /// agenda_tasks / agenda_events) are tolerated on READ via the `try?` wrapping in
    /// `PropertyDefinition.init(from:)` — they degrade to `nil` and the def is dropped
    /// by `droppingUserRelations()`. Tier-only tolerance; retired from user creation.
    enum RelationTarget: Codable, Equatable, Hashable, Sendable {
        /// Internal-only: built-in Spaces / Topics / Projects context tiers (tier 1 / 2 / 3).
        /// Tier-only tolerance; retired from user creation.
        case contextTier(Int)

        private enum CodingKeys: String, CodingKey {
            case kind
            case tier
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "context_tier":
                self = .contextTier(try c.decode(Int.self, forKey: .tier))
            default:
                // All non-context_tier kinds are retired user cases. This throw is caught by
                // the try? in PropertyDefinition.init(from:) — the sidecar still loads.
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "Unknown RelationTarget.kind: \(kind)"
                )
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .contextTier(let tier):
                try c.encode("context_tier", forKey: .kind)
                try c.encode(tier, forKey: .tier)
            }
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, type, icon
        case numberFormat = "number_format"
        case dateIncludesTime = "date_includes_time"
        case selectOptions = "select_options"
        case statusGroups = "status_groups"
        /// New canonical key (Phase 7).
        case relationTarget = "relation_target"
        /// Legacy key (pre-Phase 7). Read-tolerated; never emitted.
        case legacyRelationScope = "relation_scope"
        case reverseName = "reverse_name"
        case reverseIcon = "reverse_icon"
        case accept
        case displayAs = "display_as"
        case dateFormat = "date_format"
        case timeFormat = "time_format"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy decode: pre-v0.3.0 schemas lack the `id` field. Synthesise "" — the
        // adoption-scan migration backfills with a minted ULID before re-saving.
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.name = try c.decode(String.self, forKey: .name)
        // Retire the date-only `.date` type: fold it into the unified `.datetime`
        // ("Date") on read. The old type vanishes from the UI immediately and the
        // file rewrites to the unified form on its next save (normalize-on-read).
        // Date-only display is preserved by `timeFormat` defaulting to `.none`.
        let decodedType = try c.decode(PropertyType.self, forKey: .type)
        self.type = (decodedType == .date) ? .datetime : decodedType
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.numberFormat = try c.decodeIfPresent(NumberFormat.self, forKey: .numberFormat)
        self.dateIncludesTime = try c.decodeIfPresent(Bool.self, forKey: .dateIncludesTime)
        self.selectOptions = try c.decodeIfPresent([SelectOption].self, forKey: .selectOptions)
        self.statusGroups = try c.decodeIfPresent([StatusGroup].self, forKey: .statusGroups)
        // Dual-key tolerance: accept both the new "relation_target" key and the
        // legacy "relation_scope" key. New key takes precedence; legacy is the fallback.
        // Wrapped in try? so a retired user-relation target (e.g. page_type, agenda_tasks)
        // degrades gracefully to nil rather than failing the whole sidecar decode.
        // The def (still type: .relation) is dropped by the upstream droppingUserRelations()
        // filter; tier-only tolerance boundary.
        self.relationTarget =
            ((try? c.decodeIfPresent(RelationTarget.self, forKey: .relationTarget)) ?? nil)
            ?? ((try? c.decodeIfPresent(RelationTarget.self, forKey: .legacyRelationScope)) ?? nil)
        self.reverseName = try c.decodeIfPresent(String.self, forKey: .reverseName)
        self.reverseIcon = try c.decodeIfPresent(String.self, forKey: .reverseIcon)
        self.accept = try c.decodeIfPresent([String].self, forKey: .accept)
        self.displayAs = try c.decodeIfPresent(DisplayVariant.self, forKey: .displayAs)
        self.dateFormat = try c.decodeIfPresent(DateFormat.self, forKey: .dateFormat)
        self.timeFormat = try c.decodeIfPresent(TimeFormat.self, forKey: .timeFormat)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(numberFormat, forKey: .numberFormat)
        try c.encodeIfPresent(dateIncludesTime, forKey: .dateIncludesTime)
        try c.encodeIfPresent(selectOptions, forKey: .selectOptions)
        try c.encodeIfPresent(statusGroups, forKey: .statusGroups)
        // Always emit the new canonical key; never emit "relation_scope".
        try c.encodeIfPresent(relationTarget, forKey: .relationTarget)
        try c.encodeIfPresent(reverseName, forKey: .reverseName)
        try c.encodeIfPresent(reverseIcon, forKey: .reverseIcon)
        try c.encodeIfPresent(accept, forKey: .accept)
        try c.encodeIfPresent(displayAs, forKey: .displayAs)
        try c.encodeIfPresent(dateFormat, forKey: .dateFormat)
        try c.encodeIfPresent(timeFormat, forKey: .timeFormat)
    }

    // MARK: - SQLite index config blob

    /// Serialises this definition's type-specific config fields into the JSON
    /// blob stored in `property_definitions.config`. Single source of truth for
    /// that column — used by both `IndexBuilder` (full rebuild) and
    /// `IndexUpdater` (incremental upsert) so a row written by either path
    /// round-trips identically (notably `relation_target`, decoded back out by
    /// `IndexUpdater.reconcileContextLinks` to derive `context_links.target_kind`).
    /// `relation_target` is encoded via `RelationTarget`'s own Codable, so the
    /// on-disk and in-DB shapes match. `nonisolated`: pure computation, callable
    /// from `IndexBuilder`'s off-actor GRDB-write closures.
    nonisolated func indexConfigJSON() -> String {
        struct ConfigOnly: Encodable {
            var numberFormat: PropertyDefinition.NumberFormat?
            var dateIncludesTime: Bool?
            var selectOptions: [PropertyDefinition.SelectOption]?
            var statusGroups: [PropertyDefinition.StatusGroup]?
            var relationTarget: PropertyDefinition.RelationTarget?
            var accept: [String]?

            enum CodingKeys: String, CodingKey {
                case numberFormat = "number_format"
                case dateIncludesTime = "date_includes_time"
                case selectOptions = "select_options"
                case statusGroups = "status_groups"
                case relationTarget = "relation_target"
                case accept
            }
        }
        let config = ConfigOnly(
            numberFormat: numberFormat,
            dateIncludesTime: dateIncludesTime,
            selectOptions: selectOptions,
            statusGroups: statusGroups,
            relationTarget: relationTarget,
            accept: accept
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        guard let data = try? encoder.encode(config),
            let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }
}

// MARK: - Decode-time filter

extension Array where Element == PropertyDefinition {
    /// User relations retired; tiers are synthesized at runtime. Drop stored `.relation` defs on decode,
    /// EXCEPT reserved tier ids (`_tier1/2/3`) — those persist a user's reverse-name/icon override.
    func droppingUserRelations() -> [PropertyDefinition] {
        filter { $0.type != .relation || ReservedPropertyID.isReserved($0.id) }
    }
}
