// Pommora/Pommora/Vaults/SavedView.swift
import Foundation

/// A saved view configuration on a PageType / ItemType / PageCollection /
/// ItemCollection. v0.3.1 ships the Table-only single-saved-view case; the
/// multi-saved-view tabs row + non-Table renderers (board / list / cards /
/// gallery) land at v0.5.0.
///
/// Identity is the stored `id` ("view_<ULID>") so the View Settings popover
/// can bind `views[0]` (or future `views[i]`) without index drift across
/// saves.
///
/// Per-view config touches at v0.3.1:
///   - `visibleProperties` / `hiddenProperties` — drives `PropertyVisibilityPane`
///     + `PropertyColumnBuilder` (Phase G).
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
    var visibleProperties: [String]  // ordered property IDs that show as columns
    var hiddenProperties: [String]  // muted-strikethrough in Property Visibility pane

    // Reserved Codable stubs — not consumed at v0.3.1:
    var sort: [SortCriterion]?  // v0.3.1.2
    var filter: FilterGroup?  // v0.3.1.3
    var group: GroupConfig?  // v0.3.1.4

    init(
        id: String,
        name: String = "Table",
        icon: String? = "tablecells",
        type: ViewType = .table,
        visibleProperties: [String] = [],
        hiddenProperties: [String] = [],
        sort: [SortCriterion]? = nil,
        filter: FilterGroup? = nil,
        group: GroupConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.type = type
        self.visibleProperties = visibleProperties
        self.hiddenProperties = hiddenProperties
        self.sort = sort
        self.filter = filter
        self.group = group
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, type
        case visibleProperties = "visible_properties"
        case hiddenProperties = "hidden_properties"
        case sort, filter, group
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Table"
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.type = (try? c.decode(ViewType.self, forKey: .type)) ?? .table
        self.visibleProperties = try c.decodeIfPresent([String].self, forKey: .visibleProperties) ?? []
        self.hiddenProperties = try c.decodeIfPresent([String].self, forKey: .hiddenProperties) ?? []
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
        try c.encode(visibleProperties, forKey: .visibleProperties)
        try c.encode(hiddenProperties, forKey: .hiddenProperties)
        try c.encodeIfPresent(sort, forKey: .sort)
        try c.encodeIfPresent(filter, forKey: .filter)
        try c.encodeIfPresent(group, forKey: .group)
    }

    /// Default Table view minted by `loadAll` migrations when a container's
    /// `views` array is empty (per quirk #15 defensive-on-load pattern).
    /// `visiblePropertyIDs` carries the parent Type's `properties.map(\.id)`
    /// so every user-defined column is visible by default; the migration
    /// gives users a sensible starting view they can then customize.
    static func defaultTable(visiblePropertyIDs: [String]) -> SavedView {
        SavedView(
            id: "view_\(ULID.generate())",
            name: "Table",
            icon: "tablecells",
            type: .table,
            visibleProperties: visiblePropertyIDs,
            hiddenProperties: []
        )
    }
}

/// View renderer kind. Only `.table` is wired at v0.3.1; the remaining cases
/// are forward-declared so future-view sidecars don't break v0.3.1 decodes
/// and so the Layout pane can render them as muted/placeholder rows today.
enum ViewType: String, Codable, Equatable, Hashable, Sendable {
    case table
    case board
    case list
    case cards
    case gallery
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

/// Group-by config. Single property at v0.3.1.4 (may defer to v0.5.0 with
/// Board view). `order` overrides default group ordering (option order for
/// Select/Status; chronological for Date; etc.).
struct GroupConfig: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var order: [String]?

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case order
    }
}
