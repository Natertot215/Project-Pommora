// Pommora/Pommora/Vaults/SavedView.swift
import Foundation

/// A saved view configuration on a PageType / PageCollection.
/// v0.3.1 ships the Table-only single-saved-view case; the
/// multi-saved-view tabs row + non-Table renderers (board / list / cards /
/// gallery) land at v0.5.0.
///
/// Identity is the stored `id` ("view_<ULID>") so the View Settings popover
/// can bind `views[0]` (or future `views[i]`) without index drift across
/// saves.
///
/// Per-view config touches:
///   - `propertyOrder` / `hiddenProperties` — drives `PropertyVisibilityPane`
///     + `PropertyColumnBuilder`. `propertyOrder` always leads with the
///     reserved `_title` id. Legacy `visible_properties` sidecars are decoded
///     one-time into `["_title"] + legacy`; the key is never re-encoded.
///   - `columnWidths` / `collapsedGroups` / `cardSize` / `showCover` — layout
///     state for the Table / Board / Cards renderers (all optional).
///   - `type` — only `.table` is rendered; other cases mute in the Layout pane.
///
/// `sort` / `filter` / `group` are reserved Codable stubs at v0.3.1 — fields
/// land in the schema today so v0.3.1.x follow-up patches don't break decode
/// of v0.3.1-era sidecars when they wire the real UI:
///   - `sort`  → v0.3.1.2 Sort pane
///   - `filter` → v0.3.1.3 Filter pane
///   - `group`  → v0.3.1.4 Group pane (may defer to v0.5.0)
///
/// Decode is defensive: every field flows through `decodeIfPresent` with a
/// safe default so a stale empty `{}` from the pre-v0.3.1 stub decodes as a
/// sane placeholder. Task 5's `loadAll` default-view migration replaces any
/// container whose `views` is empty with a freshly-minted Table view.
struct SavedView: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String  // "view_<ULID>"
    var name: String  // "Table" default
    var icon: String?  // SF Symbol; default "tablecells" when minted by ensureDefaultView
    var type: ViewType  // .table at v0.3.1; others muted
    var propertyOrder: [String]  // ordered property IDs (always leads with `_title`)
    var hiddenProperties: [String]  // muted-strikethrough in Property Visibility pane

    // Layout state — all optional (absent on legacy / freshly-minted sidecars):
    var columnWidths: [String: Double]?  // per-column width in points, keyed by property ID
    var collapsedGroups: [String]?  // collapsed group keys (Board / grouped Table)
    var cardSize: CardSize?  // Cards / Gallery card sizing
    var showCover: Bool?  // nil/false = covers hidden (the default)

    // Reserved Codable stubs — not consumed at v0.3.1:
    var sort: [SortCriterion]?  // v0.3.1.2
    var filter: FilterGroup?  // v0.3.1.3
    var group: GroupConfig?  // v0.3.1.4

    init(
        id: String,
        name: String = "Table",
        icon: String? = "tablecells",
        type: ViewType = .table,
        propertyOrder: [String] = [],
        hiddenProperties: [String] = [],
        columnWidths: [String: Double]? = nil,
        collapsedGroups: [String]? = nil,
        cardSize: CardSize? = nil,
        showCover: Bool? = nil,
        sort: [SortCriterion]? = nil,
        filter: FilterGroup? = nil,
        group: GroupConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.type = type
        self.propertyOrder = propertyOrder
        self.hiddenProperties = hiddenProperties
        self.columnWidths = columnWidths
        self.collapsedGroups = collapsedGroups
        self.cardSize = cardSize
        self.showCover = showCover
        self.sort = sort
        self.filter = filter
        self.group = group
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, type
        case propertyOrder = "property_order"
        case legacyVisibleProperties = "visible_properties"  // decode-only
        case hiddenProperties = "hidden_properties"
        case columnWidths = "column_widths"
        case collapsedGroups = "collapsed_groups"
        case cardSize = "card_size"
        case showCover = "show_cover"
        case sort, filter, group
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Table"
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.type = (try? c.decode(ViewType.self, forKey: .type)) ?? .table
        // `property_order` is canonical; a legacy `visible_properties` sidecar
        // migrates one-time to `["_title"] + legacy`. The legacy key is never
        // re-encoded, so the next save drops it.
        if let order = try c.decodeIfPresent([String].self, forKey: .propertyOrder) {
            self.propertyOrder = order
        } else if let legacy = try c.decodeIfPresent([String].self, forKey: .legacyVisibleProperties) {
            self.propertyOrder = [ReservedPropertyID.title] + legacy
        } else {
            self.propertyOrder = []
        }
        self.hiddenProperties = try c.decodeIfPresent([String].self, forKey: .hiddenProperties) ?? []
        self.columnWidths = try c.decodeIfPresent([String: Double].self, forKey: .columnWidths)
        self.collapsedGroups = try c.decodeIfPresent([String].self, forKey: .collapsedGroups)
        self.cardSize = try c.decodeIfPresent(CardSize.self, forKey: .cardSize)
        self.showCover = try c.decodeIfPresent(Bool.self, forKey: .showCover)
        self.sort = try c.decodeIfPresent([SortCriterion].self, forKey: .sort)
        self.filter = try c.decodeIfPresent(FilterGroup.self, forKey: .filter)
        self.group = try c.decodeIfPresent(GroupConfig.self, forKey: .group)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encode(type, forKey: .type)
        try c.encode(propertyOrder, forKey: .propertyOrder)
        try c.encode(hiddenProperties, forKey: .hiddenProperties)
        try c.encodeIfPresent(columnWidths, forKey: .columnWidths)
        try c.encodeIfPresent(collapsedGroups, forKey: .collapsedGroups)
        try c.encodeIfPresent(cardSize, forKey: .cardSize)
        try c.encodeIfPresent(showCover, forKey: .showCover)
        try c.encodeIfPresent(sort, forKey: .sort)
        try c.encodeIfPresent(filter, forKey: .filter)
        try c.encodeIfPresent(group, forKey: .group)
    }

    /// Default Table view minted by `loadAll` migrations when a container's
    /// `views` array is empty (per quirk #15 defensive-on-load pattern).
    /// `visiblePropertyIDs` carries the parent Type's `properties.map(\.id)`
    /// so every user-defined column is visible by default; the migration
    /// gives users a sensible starting view they can then customize.
    ///
    /// `defaultSort` folds the parent Type's legacy `default_sort` sidecar
    /// field into the minted view's `sort` so the previously-persisted default
    /// ordering carries forward. `PageType.defaultSort` keeps DECODING but is
    /// never written again — the SavedView's `sort` is now authoritative.
    /// Muted right-aligned type label for the Views dropdown row:
    /// `"Table"` for non-gallery views; `"Gallery | Medium"` for gallery views
    /// (pipe + capitalized CardSize word). Single source for the row label so
    /// the panel + Component Library staging stay in lockstep.
    var typeLabel: String {
        switch type {
        case .gallery:
            return "\(type.displayName) | \((cardSize ?? .medium).displayName)"
        default:
            return type.displayName
        }
    }

    static func defaultTable(
        visiblePropertyIDs: [String],
        defaultSort: DefaultSortConfig? = nil
    ) -> SavedView {
        let sort = defaultSort.map { config in
            [
                SortCriterion(
                    propertyID: config.propertyID,
                    direction: config.direction == .ascending ? .ascending : .descending
                )
            ]
        }
        return SavedView(
            id: "view_\(ULID.generate())",
            name: "Table",
            icon: "tablecells",
            type: .table,
            propertyOrder: [ReservedPropertyID.title] + visiblePropertyIDs,
            hiddenProperties: [],
            sort: sort
        )
    }
}

/// Card sizing for the Cards / Gallery renderers. `columnsPerRow` is the
/// grid density each size maps to (smaller card → more columns per row).
enum CardSize: String, Codable, Equatable, Hashable, Sendable {
    case small
    case medium
    case large

    var columnsPerRow: Int {
        switch self {
        case .small: return 8
        case .medium: return 6
        case .large: return 4
        }
    }
}

/// View renderer kind. Only `.table` is wired at v0.3.1; the remaining cases
/// are forward-declared so future-view sidecars don't break v0.3.1 decodes
/// and so the Layout pane can render them as muted/placeholder rows today.
enum ViewType: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case table
    case board
    case list
    case cards
    case gallery

    /// Capitalized display name ("Table", "Gallery") for the Views dropdown
    /// type label + the inline type-switch rows.
    var displayName: String {
        switch self {
        case .table: return "Table"
        case .board: return "Board"
        case .list: return "List"
        case .cards: return "Cards"
        case .gallery: return "Gallery"
        }
    }

    /// SF Symbol minted onto a freshly-added view of this type.
    var defaultIcon: String {
        switch self {
        case .table: return "tablecells"
        case .board: return "rectangle.split.3x1"
        case .list: return "list.bullet"
        case .cards: return "rectangle.grid.2x2"
        case .gallery: return "square.grid.3x3"
        }
    }

    /// Renderers wired today (the dropdown's inline type-switch offers these as
    /// active rows; the rest render muted). Table + Gallery ship at this task.
    var isImplemented: Bool {
        switch self {
        case .table, .gallery: return true
        case .board, .list, .cards: return false
        }
    }
}

/// Capitalized display word for the Gallery card-size suffix
/// ("Gallery | Small"). Single source for the dropdown type label.
extension CardSize {
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

// MARK: - Reserved Codable stubs (v0.3.1.x follow-up patches consume these)

/// Single sort criterion. Multi-criterion ordering lives in `SavedView.sort`
/// as `[SortCriterion]` (priority = array order). Wires up at v0.3.1.2.
struct SortCriterion: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var direction: SortDirection

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case direction
    }
}

// `SortDirection` is declared once at `Pommora/Index/IndexQuery.swift`
// (shared with the index-query layer); we extended its conformance list with
// Codable + Equatable + Hashable as part of Task 3 so it can serve both
// surfaces without redeclaring.

/// Group of filter rules combined by `match` (all = AND, any = OR). AND-only
/// at v0.3.1.3 ship; OR-mode promised at v0.5.0.
struct FilterGroup: Codable, Equatable, Hashable, Sendable {
    var match: MatchMode
    var rules: [FilterRule]
}

/// One filter rule. `op` + `value` are serialized as raw strings at v0.3.1 so
/// the schema is forward-compatible with the v0.3.1.3 operator-enum + value-
/// union without breaking existing decodes.
struct FilterRule: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var op: String  // serialized operator name — full enum lands v0.3.1.3
    var value: String?  // serialized payload — full union lands v0.3.1.3

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case op, value
    }
}

enum MatchMode: String, Codable, Equatable, Hashable, Sendable {
    case all
    case any
}

/// Property-grouping payload for `GroupConfig.property`. `order` overrides the
/// default group ordering (option order for Select/Status; chronological for
/// Date; etc.); omitted on encode when nil.
struct PropertyGrouping: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var order: [String]?

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case order
    }
}

/// Group-by config — a discriminated value over three grouping modes:
///   - `.structural` — group by the natural container (Collection / Set).
///   - `.property` — group by a property's value (`PropertyGrouping`).
///   - `.flat` — no grouping.
///
/// Serialized as a tagged object on a `kind` discriminator
/// (`{"kind":"structural"}` / `{"kind":"property","property_id":…,"order":…}` /
/// `{"kind":"flat"}`). Decode is **lenient**: `GroupConfig` is read as part of
/// the whole `SavedView` sidecar, so a malformed or unknown shape must never
/// throw (a throw poisons the entire sidecar decode). The legacy v0.3.1 stub
/// `{"property_id":…}` (no `kind`) keeps decoding as `.property`; any unknown
/// `kind` falls back to `.structural`.
enum GroupConfig: Codable, Equatable, Hashable, Sendable {
    case structural
    case property(PropertyGrouping)
    case flat

    private enum CodingKeys: String, CodingKey {
        case kind
        case propertyID = "property_id"
        case order
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        switch kind {
        case "structural":
            self = .structural
        case "flat":
            self = .flat
        case "property":
            self = .property(Self.decodeProperty(from: c))
        case nil:
            // Legacy v0.3.1 stub: a bare `{"property_id":…}` with no `kind`.
            if c.contains(.propertyID) {
                self = .property(Self.decodeProperty(from: c))
            } else {
                self = .structural
            }
        default:
            // Unknown discriminator — lenient fallback (never throw).
            self = .structural
        }
    }

    private static func decodeProperty(
        from c: KeyedDecodingContainer<CodingKeys>
    ) -> PropertyGrouping {
        let propertyID = (try? c.decode(String.self, forKey: .propertyID)) ?? ""
        let order = try? c.decodeIfPresent([String].self, forKey: .order)
        return PropertyGrouping(propertyID: propertyID, order: order ?? nil)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .structural:
            try c.encode("structural", forKey: .kind)
        case .flat:
            try c.encode("flat", forKey: .kind)
        case .property(let grouping):
            try c.encode("property", forKey: .kind)
            try c.encode(grouping.propertyID, forKey: .propertyID)
            try c.encodeIfPresent(grouping.order, forKey: .order)
        }
    }
}
