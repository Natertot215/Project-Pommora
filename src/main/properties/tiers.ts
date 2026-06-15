// Tier context-link property synthesis. The effective schema a Type exposes is its
// stored user definitions followed by the three pre-configured tier relation properties
// (_tier1/2/3). Pure — mirrors Swift's BuiltInContextLinkProperties.merge. The tiers are
// synthesized at read time, never stored; only a user's reverse-name/icon override
// persists as a reserved `_tierN` entry in the sidecar.

import { RESERVED_PROPERTY_ID, isReservedPropertyId, type PropertyDefinition } from '@shared/properties'

const FALLBACK_ICON = 'square.grid.2x2'

const DESCRIPTORS: { id: string; level: number }[] = [
  { id: RESERVED_PROPERTY_ID.tier1, level: 1 },
  { id: RESERVED_PROPERTY_ID.tier2, level: 2 },
  { id: RESERVED_PROPERTY_ID.tier3, level: 3 }
]

/** The Type's user-defined properties followed by the three merged tier properties.
 *  Merge rules (per Swift):
 *  - name: sidecar override → `tierPlural(level)` → "Tier N"
 *  - icon: sidecar override → fallback
 *  - relation_target: structurally locked to `{ context_tier, level }` (sidecar ignored)
 *  - reverse_name / reverse_icon: propagate from the sidecar override if present
 *
 *  `tierPlural` supplies the per-nexus tier label (from tier-config.json once that
 *  singleton lands); a missing label falls back to "Tier N". */
export function mergeTierProperties(
  stored: PropertyDefinition[],
  tierPlural?: (level: number) => string | undefined
): PropertyDefinition[] {
  // Keep user-defined props (+ a reserved `_modified_at` column override if present);
  // strip every existing tier / reserved entry so we re-emit canonical tier props.
  const userDefined = stored.filter(
    (d) => !isReservedPropertyId(d.id) || d.id === RESERVED_PROPERTY_ID.modifiedAt
  )

  const tiers: PropertyDefinition[] = DESCRIPTORS.map((d) => {
    const sidecar = stored.find((s) => s.id === d.id)
    const def: PropertyDefinition = {
      id: d.id,
      name: sidecar?.name ?? tierPlural?.(d.level) ?? `Tier ${d.level}`,
      type: 'relation',
      icon: sidecar?.icon ?? FALLBACK_ICON,
      relation_target: { kind: 'context_tier', tier: d.level }
    }
    if (sidecar?.reverse_name !== undefined) def.reverse_name = sidecar.reverse_name
    if (sidecar?.reverse_icon !== undefined) def.reverse_icon = sidecar.reverse_icon
    return def
  })

  return [...userDefined, ...tiers]
}
