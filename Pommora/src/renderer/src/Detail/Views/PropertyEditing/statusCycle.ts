// Status group mechanics shared by every container view's cells — the capsule/checkbox glyphs
// key off the group, and the checkbox-look click cycle steps through them.

import type { IconName } from '@renderer/design-system/symbols'
import type { PropertyDefinition, StatusGroupId } from '@shared/properties'

const STATUS_GROUP_GLYPH: Record<string, IconName> = {
  upcoming: 'circle-dashed',
  in_progress: 'minus',
  done: 'check'
}

/** A group's glyph for the capsule/checkbox cell looks + the picker's capsule options. An unknown or
 *  absent group (reachable only via malformed data today) falls back to the neutral dashed circle. */
export function statusGroupGlyph(group: string | undefined): IconName {
  return (group ? STATUS_GROUP_GLYPH[group] : undefined) ?? 'circle-dashed'
}

/** The group a status value belongs to (undefined for an unknown value or a missing def). */
export function statusGroupOf(value: string, def: PropertyDefinition | undefined): StatusGroupId | undefined {
  for (const g of def?.status_groups ?? []) {
    if (g.options.some((o) => o.value === value)) return g.id
  }
  return undefined
}

const CYCLE: StatusGroupId[] = ['upcoming', 'in_progress', 'done']

/** The checkbox-look click cycle: advance to the NEXT group and write its first-in-order option
 *  (empty box = upcoming → minus → check → empty box), skipping option-less groups. A null or
 *  unknown current reads as the empty box. Null when no group holds any option. */
export function nextCycleValue(current: string | undefined, def: PropertyDefinition | undefined): string | null {
  const byId = new Map((def?.status_groups ?? []).map((g) => [g.id, g]))
  const from = CYCLE.indexOf(statusGroupOf(current ?? '', def) ?? 'upcoming')
  for (let step = 1; step <= CYCLE.length; step++) {
    const g = byId.get(CYCLE[(from + step) % CYCLE.length])
    if (g && g.options.length > 0) return g.options[0].value
  }
  return null
}
