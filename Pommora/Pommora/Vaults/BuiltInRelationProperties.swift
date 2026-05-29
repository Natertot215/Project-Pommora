import Foundation

/// Produces the three pre-configured tier relation PropertyDefinitions
/// (`_tier1` / `_tier2` / `_tier3`) merged with any per-Type sidecar overrides.
/// Pure logic — no I/O, no environment, no UI.
enum BuiltInRelationProperties {
    private struct TierDescriptor {
        let id: String
        let tierNumber: Int
        let fallbackIcon: String
    }

    private static let descriptors: [TierDescriptor] = [
        TierDescriptor(id: ReservedPropertyID.tier1, tierNumber: 1, fallbackIcon: "building.2"),
        TierDescriptor(id: ReservedPropertyID.tier2, tierNumber: 2, fallbackIcon: "tag"),
        TierDescriptor(id: ReservedPropertyID.tier3, tierNumber: 3, fallbackIcon: "briefcase"),
    ]

    /// Returns the schema's user-defined properties followed by the three merged
    /// tier relation properties.
    ///
    /// Merge rules:
    /// - Display name: sidecar override → TierConfig plural → "Tier N" fallback.
    /// - Icon: sidecar override → hardcoded fallback.
    ///   TODO: icon override beyond sidecar→fallback awaits a future IconConfig effort.
    /// - `relationTarget` is structurally locked to `.contextTier(N)` — any sidecar
    ///   `relationTarget` value is ignored.
    /// - `reverseName` / `reverseIcon` propagate from the sidecar if present.
    ///
    /// - Parameters:
    ///   - existing: The full property list currently stored in the sidecar.
    ///   - tierConfig: The nexus-level tier label configuration.
    ///   - sourceTypeID: ID of the PageType / ItemType being merged (reserved for
    ///     future logging / per-type overrides; currently unused by this function body).
    static func merge(
        existing: [PropertyDefinition],
        tierConfig: TierConfig,
        sourceTypeID: String
    ) -> [PropertyDefinition] {
        _ = sourceTypeID  // signature-stable; future phases / logging will consume this

        // Keep user-defined props and _modified_at; strip any existing tier / reserved entries
        // so we can re-emit the tiers in canonical merged form at the end.
        let userDefined = existing.filter {
            !ReservedPropertyID.isReserved($0.id) || $0.id == ReservedPropertyID.modifiedAt
        }

        let tierEntries: [PropertyDefinition] = descriptors.map { d in
            let sidecar = existing.first { $0.id == d.id }
            let tier = tierConfig.tiers.first { $0.level == d.tierNumber }

            return PropertyDefinition(
                id: d.id,
                name: sidecar?.name ?? tier?.plural ?? "Tier \(d.tierNumber)",
                type: .relation,
                icon: sidecar?.icon ?? d.fallbackIcon,
                relationTarget: .contextTier(d.tierNumber),  // locked; sidecar override ignored
                reverseName: sidecar?.reverseName,
                reverseIcon: sidecar?.reverseIcon
            )
        }

        return userDefined + tierEntries
    }
}
