// Status group mechanics shared by every container view's cells — the capsule/checkbox glyphs
// key off the fixed group, and the checkbox-look click cycle steps through the groups.

import type { PropertyDefinition, StatusGroupId } from '@shared/properties'

/** The fixed group a status value belongs to (undefined for an unknown value or a missing def). */
export function statusGroupOf(value: string, def: PropertyDefinition | undefined): StatusGroupId | undefined {
  for (const g of def?.status_groups ?? []) {
    if (g.options.some((o) => o.value === value)) return g.id
  }
  return undefined
}
