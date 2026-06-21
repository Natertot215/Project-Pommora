import Foundation

/// One source of truth for the relation read/write routing shared by every
/// entity that carries the three built-in tier relations at its root plus
/// arbitrary user relations inside `properties`: `PageFrontmatter`,
/// `AgendaTask`, `AgendaEvent`.
///
/// The default implementations route the three pre-configured tier properties
/// (`tier1` / `tier2` / `tier3`) to their dedicated root fields and any other
/// relation property to `properties`. An empty user-relation value OMITS the
/// key on write (no empty array on disk) so the schema-blind decoder never sees
/// an ambiguous `[]`. Tier writes always set the array (a tier is a fixed root
/// field, never omitted).
protocol TierRelationCarrying {
    var tier1: [String] { get set }
    var tier2: [String] { get set }
    var tier3: [String] { get set }
    var properties: [String: PropertyValue] { get set }
}

extension TierRelationCarrying {
    /// Canonical READ for any relation-typed property, including the three
    /// built-in tier properties whose values live at the entity root.
    func relationIDs(forPropertyID id: String) -> [String] {
        switch id {
        case ReservedPropertyID.tier1: return tier1
        case ReservedPropertyID.tier2: return tier2
        case ReservedPropertyID.tier3: return tier3
        default:
            if case .relation(let ids)? = properties[id] { return ids }
            return []
        }
    }

    /// Canonical WRITE. Tier IDs route to the root field; user relations route to
    /// `properties`. An empty user-relation value OMITS the key (no empty array on
    /// disk) so the schema-blind decoder never sees an ambiguous `[]`.
    mutating func setRelationIDs(_ ids: [String], forPropertyID id: String) {
        switch id {
        case ReservedPropertyID.tier1: tier1 = ids
        case ReservedPropertyID.tier2: tier2 = ids
        case ReservedPropertyID.tier3: tier3 = ids
        default: properties[id] = ids.isEmpty ? nil : .relation(ids)
        }
    }

    /// The current cell value a property editor reads for `definition`: a
    /// relation property wraps its (tier-aware) id list as `.relation`, any other
    /// type passes through the stored `properties` value. Single source for the
    /// relation-vs-scalar read shared by the table + gallery cell renderers.
    func cellValue(for definition: PropertyDefinition) -> PropertyValue? {
        if definition.type == .relation {
            return .relation(relationIDs(forPropertyID: definition.id))
        }
        return properties[definition.id]
    }
}
