import { isValidLink, normalizeLinkUrl } from '@shared/links'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { serializeLink } from '../Table/linkValue'

/** The pickers that open a value PANE (chip/option pickers) — grouped to the top of the property
 *  picker; simpler kinds (date/number/url/checkbox) fall to the bottom. */
const PANE_KINDS: ReadonlySet<string> = new Set(['status', 'select', 'multi_select', 'context'])

/** Property-picker list order: pane-bearing pickers to the top, everything else to the bottom, with
 *  property order preserved WITHIN each group (a stable partition). Shared by the in-app add-picker
 *  and the native Add-Property menu so both read the same. */
export function orderAddableDefs(defs: PropertyDefinition[]): PropertyDefinition[] {
  return [
    ...defs.filter((d) => PANE_KINDS.has(d.type)),
    ...defs.filter((d) => !PANE_KINDS.has(d.type)),
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
