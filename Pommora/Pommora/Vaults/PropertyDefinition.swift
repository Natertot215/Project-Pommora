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
    var dualProperty: DualPropertyConfig?  // relation — paired reverse on target Type
    var accept: [String]?  // file — MIME-type whitelist (e.g. ["application/pdf", "image/*"])
    var displayAs: DisplayVariant?  // status — render variant (nil = .box default)
    var dateFormat: DateFormat?  // date / datetime — display format (nil = .monthDayYearLong default)

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
        dualProperty: DualPropertyConfig? = nil,
        accept: [String]? = nil,
        displayAs: DisplayVariant? = nil,
        dateFormat: DateFormat? = nil
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
        self.dualProperty = dualProperty
        self.accept = accept
        self.displayAs = displayAs
        self.dateFormat = dateFormat
    }

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

    /// Paired-relation config (per Properties.md § "Dual relations"). Container-scoped
    /// relations (`page_type` / `item_type` / `page_collection` / `item_collection`) MUST
    /// carry this; `context_tier` rejects it (Contexts have no `properties[]` schema).
    /// Both sides' configs reference each other by property ID — rename-safe per L2.
    struct DualPropertyConfig: Codable, Equatable, Hashable, Sendable {
        var syncedPropertyID: String  // the reverse property's ID on the target Type
        var syncedPropertyDefinedOnTypeID: String  // the target Type's ID (never a Collection)

        enum CodingKeys: String, CodingKey {
            case syncedPropertyID = "synced_property_id"
            case syncedPropertyDefinedOnTypeID = "synced_property_defined_on_type_id"
        }
    }

    /// Picker constraint for a Relation property. Seven mutually-exclusive target kinds;
    /// no fallback "anywhere" target (per Properties.md § "Relation scope").
    ///
    /// On-disk shape is a tagged object: `{"kind": "<discriminator>", "<id-field>": "..."}`.
    /// Container targets (page_type / item_type / page_collection / item_collection) carry
    /// a target ULID; context_tier carries the tier number (1/2/3). Agenda targets carry
    /// no additional payload.
    ///
    /// Container targets are mandatorily paired with a `dual_property` reverse on the target
    /// Type's sidecar; context_tier and agenda targets reject dual (the reverse view is
    /// SQLite-query-derived).
    enum RelationTarget: Codable, Equatable, Hashable, Sendable {
        /// User-creatable: targets a specific Page Type by ULID.
        case pageType(String)
        /// User-creatable: targets a specific Item Type by ULID.
        case itemType(String)
        /// LEGACY — decoded for tolerance only; migration rewrites to the parent type in a later phase.
        case pageCollection(String)
        /// LEGACY — decoded for tolerance only; migration rewrites to the parent type in a later phase.
        case itemCollection(String)
        /// Internal-only: built-in Spaces / Topics / Projects context tiers (tier 1 / 2 / 3).
        case contextTier(Int)
        /// User-creatable singleton target: all Agenda Tasks in the nexus.
        case agendaTasks
        /// User-creatable singleton target: all Agenda Events in the nexus.
        case agendaEvents

        private enum CodingKeys: String, CodingKey {
            case kind
            case pageTypeID = "page_type_id"
            case itemTypeID = "item_type_id"
            case pageCollectionID = "page_collection_id"
            case itemCollectionID = "item_collection_id"
            case tier
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "page_type":
                self = .pageType(try c.decode(String.self, forKey: .pageTypeID))
            case "item_type":
                self = .itemType(try c.decode(String.self, forKey: .itemTypeID))
            case "page_collection":
                self = .pageCollection(try c.decode(String.self, forKey: .pageCollectionID))
            case "item_collection":
                self = .itemCollection(try c.decode(String.self, forKey: .itemCollectionID))
            case "context_tier":
                self = .contextTier(try c.decode(Int.self, forKey: .tier))
            case "agenda_tasks":
                self = .agendaTasks
            case "agenda_events":
                self = .agendaEvents
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "Unknown RelationTarget.kind: \(kind)"
                )
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .pageType(let id):
                try c.encode("page_type", forKey: .kind)
                try c.encode(id, forKey: .pageTypeID)
            case .itemType(let id):
                try c.encode("item_type", forKey: .kind)
                try c.encode(id, forKey: .itemTypeID)
            case .pageCollection(let id):
                try c.encode("page_collection", forKey: .kind)
                try c.encode(id, forKey: .pageCollectionID)
            case .itemCollection(let id):
                try c.encode("item_collection", forKey: .kind)
                try c.encode(id, forKey: .itemCollectionID)
            case .contextTier(let tier):
                try c.encode("context_tier", forKey: .kind)
                try c.encode(tier, forKey: .tier)
            case .agendaTasks:
                try c.encode("agenda_tasks", forKey: .kind)
            case .agendaEvents:
                try c.encode("agenda_events", forKey: .kind)
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
        case dualProperty = "dual_property"
        case accept
        case displayAs = "display_as"
        case dateFormat = "date_format"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy decode: pre-v0.3.0 schemas lack the `id` field. Synthesise "" — the
        // adoption-scan migration backfills with a minted ULID before re-saving.
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decode(PropertyType.self, forKey: .type)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.numberFormat = try c.decodeIfPresent(NumberFormat.self, forKey: .numberFormat)
        self.dateIncludesTime = try c.decodeIfPresent(Bool.self, forKey: .dateIncludesTime)
        self.selectOptions = try c.decodeIfPresent([SelectOption].self, forKey: .selectOptions)
        self.statusGroups = try c.decodeIfPresent([StatusGroup].self, forKey: .statusGroups)
        // Dual-key tolerance: accept both the new "relation_target" key and the
        // legacy "relation_scope" key. New key takes precedence; legacy is the fallback.
        if let t = try c.decodeIfPresent(RelationTarget.self, forKey: .relationTarget) {
            self.relationTarget = t
        } else {
            self.relationTarget = try c.decodeIfPresent(RelationTarget.self, forKey: .legacyRelationScope)
        }
        self.reverseName = try c.decodeIfPresent(String.self, forKey: .reverseName)
        self.reverseIcon = try c.decodeIfPresent(String.self, forKey: .reverseIcon)
        self.dualProperty = try c.decodeIfPresent(DualPropertyConfig.self, forKey: .dualProperty)
        self.accept = try c.decodeIfPresent([String].self, forKey: .accept)
        self.displayAs = try c.decodeIfPresent(DisplayVariant.self, forKey: .displayAs)
        self.dateFormat = try c.decodeIfPresent(DateFormat.self, forKey: .dateFormat)
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
        try c.encodeIfPresent(dualProperty, forKey: .dualProperty)
        try c.encodeIfPresent(accept, forKey: .accept)
        try c.encodeIfPresent(displayAs, forKey: .displayAs)
        try c.encodeIfPresent(dateFormat, forKey: .dateFormat)
    }

    // MARK: - SQLite index config blob

    /// Serialises this definition's type-specific config fields into the JSON
    /// blob stored in `property_definitions.config`. Single source of truth for
    /// that column — used by both `IndexBuilder` (full rebuild) and
    /// `IndexUpdater` (incremental upsert) so a row written by either path
    /// round-trips identically (notably `relation_target`, decoded back out by
    /// `IndexUpdater.reconcileRelations` to derive `relations.target_kind`).
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
