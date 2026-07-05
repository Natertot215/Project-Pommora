// The resolution context threaded into table cells + group headers so they turn ids into human values
// at render (Part 2 A-4): the container schema (property names + option labels), a ULID→Context lookup
// (tier values → title + color), and the per-Nexus labels (tier headers). Built once per table render
// from the tree; pure — no fs, no React.

import type { AreaColor, NexusLabels, NexusTree } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'

/** A resolved Context reference for a tier cell — its title and (Areas only) color. */
export interface ContextRef {
  title: string
  color?: AreaColor
}

/** Everything a table cell / group header needs to resolve ids → human values at render. */
export interface ResolveContext {
  schema: PropertyDefinition[]
  contextsById: Map<string, ContextRef>
  labels: NexusLabels
}

/** ULID → {title, color} across all three context tiers. Only Areas carry a color today; Topics and
 *  Projects resolve title-only (their ContextChips fall back to a neutral tint). */
export function buildContextsById(tree: NexusTree): Map<string, ContextRef> {
  const m = new Map<string, ContextRef>()
  for (const a of tree.contexts.areas) m.set(a.id, { title: a.title, color: a.color })
  for (const t of tree.contexts.topics) m.set(t.id, { title: t.title })
  for (const p of tree.contexts.projects) m.set(p.id, { title: p.title })
  return m
}

/** Assemble the full resolution context from the tree + the container's (effective) schema. */
export function buildResolveContext(tree: NexusTree, schema: PropertyDefinition[]): ResolveContext {
  return { schema, contextsById: buildContextsById(tree), labels: tree.labels }
}
