// Renderer-side resolution of a column id → its human header label (Part 2 A-2). User properties
// resolve through the stored schema; the three context tiers resolve through the per-Nexus labels
// (NOT the main-only mergeTierProperties, which can't cross the process boundary); built-in reserved
// columns carry fixed labels. An unknown id (a stale prop_* reference) falls back to the id itself,
// never throwing — a single bad column never breaks the header row.

import type { NexusLabels } from '@shared/types'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'

// Tier level (1 = Area, 2 = Topic, 3 = Project) → the NexusLabels key holding its LabelPair.
const TIER_LABEL_KEY = ['area', 'topic', 'project'] as const

/** The per-Nexus plural label for a context tier (1 = Area, 2 = Topic, 3 = Project). */
export function tierLabel(level: number, labels: NexusLabels): string {
  const key = TIER_LABEL_KEY[level - 1]
  return key ? labels[key].plural : `Tier ${level}`
}

const TIER_LEVEL_BY_ID: Record<string, number> = {
  [RESERVED_PROPERTY_ID.tier1]: 1,
  [RESERVED_PROPERTY_ID.tier2]: 2,
  [RESERVED_PROPERTY_ID.tier3]: 3
}

// Built-in reserved columns with fixed English labels (tiers are configurable, handled above).
const RESERVED_LABEL: Record<string, string> = {
  [RESERVED_PROPERTY_ID.title]: 'Title',
  [RESERVED_PROPERTY_ID.createdAt]: 'Created',
  [RESERVED_PROPERTY_ID.modifiedAt]: 'Modified'
}

/** A column id → its header label: tiers via the per-Nexus labels, built-ins via fixed labels, user
 *  props via the schema def's `name`, an unknown id via the id itself (never throws). */
export function columnLabel(columnId: string, schema: PropertyDefinition[], labels: NexusLabels): string {
  const tier = TIER_LEVEL_BY_ID[columnId]
  if (tier) return tierLabel(tier, labels)
  return RESERVED_LABEL[columnId] ?? schema.find((d) => d.id === columnId)?.name ?? columnId
}
