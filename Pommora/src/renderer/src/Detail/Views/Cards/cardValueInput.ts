import { isValidLink, normalizeLinkUrl } from '@shared/links'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { serializeLink } from '../Table/linkValue'

/** Kinds that commit straight from the list with no drill-in value pane (no chevron). Only the
 *  checkbox is instant today; every other addable kind opens a pane and shows a chevron. */
const NO_PANE_KINDS: ReadonlySet<string> = new Set(['checkbox'])

/** Property-picker list order: every pane-bearing kind (the ones that show a `>` chevron) sorts to
 *  the top and the instant, chevron-less kinds sink to the bottom, property order preserved WITHIN
 *  each group (a stable partition). Shared by the in-app add-picker and the native Add-Property menu
 *  so both read the same. */
export function orderAddableDefs(defs: PropertyDefinition[]): PropertyDefinition[] {
  return [
    ...defs.filter((d) => !NO_PANE_KINDS.has(d.type)),
    ...defs.filter((d) => NO_PANE_KINDS.has(d.type)),
  ]
}

/** Parse a text-editor string for a number/url property into its committable value. `null` clears
 *  (empty input); `undefined` means invalid — don't commit. Shared by the card value editor and the
 *  add-picker's value pane so both parse identically. */
export function parseEditorValue(
  type: string | undefined,
  raw: string,
): PropertyValue | null | undefined {
  const trimmed = raw.trim()
  if (type === 'number') {
    if (trimmed === '') return null
    const n = Number.parseFloat(trimmed)
    return Number.isNaN(n) ? undefined : { kind: 'number', value: n }
  }
  if (type === 'url') {
    if (trimmed === '') return null
    return isValidLink(trimmed)
      ? { kind: 'url', value: serializeLink({ url: normalizeLinkUrl(trimmed) }) }
      : undefined
  }
  return undefined
}
