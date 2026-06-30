// Cross-group row drag → property reassignment (D-4). When a row is dropped into a different group,
// its grouped property is written to that group's value. Pure: no fs, no React — unit-tested.

import { UNGROUPED } from '@shared/types'
import type { PropertyValue } from '@shared/propertyValue'

/** Property types whose group key maps cleanly back to a settable value (D-4). A date bucket isn't a
 *  single date, so date/datetime grouping can't be reassigned by drag; the rest here can. */
export const REASSIGNABLE_GROUP_TYPES = new Set<string>(['status', 'select', 'checkbox'])

/** The PropertyValue a row takes when dropped into a destination group (D-4). The no-value band
 *  (UNGROUPED) clears the property; a property group's key IS the value — the option value for
 *  status/select, the bucket for checkbox. Caller restricts `type` to REASSIGNABLE_GROUP_TYPES. */
export function groupKeyToValue(groupKey: string, type: string | undefined): PropertyValue | null {
  if (groupKey === UNGROUPED) return null
  switch (type) {
    case 'status':
      return { kind: 'status', value: groupKey }
    case 'select':
      return { kind: 'select', value: groupKey }
    case 'checkbox':
      return { kind: 'checkbox', value: groupKey === 'true' }
    default:
      return null
  }
}
