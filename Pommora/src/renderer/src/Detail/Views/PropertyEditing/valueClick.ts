// The shared value-click semantics every edit surface (table cell, card value, inspector row)
// routes through BEFORE its surface-specific tail (number/url placement differs by design per
// surface). One home for the rules that must never drift: a checkbox-look status CYCLES — but an
// empty one assigns via the picker, never a blind write; a checkbox is true-or-absent on disk,
// never a stored false; the option kinds open their picker; datetime opens the calendar.

import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { nextCycleValue } from './statusCycle'

export type ValueClickAction =
  | { kind: 'commit'; value: PropertyValue | null }
  | { kind: 'picker' }
  | { kind: 'datetime' }
  | null

/** Null = the click isn't covered by the shared rules — the surface's own tail routes it. */
export function sharedValueClickAction(
  type: string | undefined,
  look: string | undefined,
  value: PropertyValue,
  def: PropertyDefinition | undefined,
): ValueClickAction {
  if (type === 'status' && look === 'checkbox') {
    const current = value.kind === 'status' || value.kind === 'select' ? value.value : undefined
    if (!current) return { kind: 'picker' }
    const next = nextCycleValue(current, def)
    return next !== null ? { kind: 'commit', value: { kind: 'status', value: next } } : null
  }
  if (type === 'checkbox') {
    const checked = value.kind === 'checkbox' && value.value
    return { kind: 'commit', value: checked ? null : { kind: 'checkbox', value: true } }
  }
  if (type === 'status' || type === 'select' || type === 'multi_select' || type === 'context')
    return { kind: 'picker' }
  if (type === 'datetime') return { kind: 'datetime' }
  return null
}
