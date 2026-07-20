import { isValidLink, normalizeLinkUrl } from '@shared/links'
import type { PropertyDefinition, PropertyType } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { serializeLink } from '../Table/linkValue'

/** One row of the card add-property menu (something NOT currently shown). A `pane` entry (a blank
 *  addable-type prop) drills into a value pane to set a value; a `revealOnly` entry (a hidden
 *  tier/context, a filled prop, or a checkbox) just unhides on pick. `def` is null for a reserved
 *  tier/Modified id, which carries no schema entry. */
export type AddEntry = {
  id: string
  name: string
  type: PropertyType
  def: PropertyDefinition | null
  revealOnly: boolean
}

/** Menu order: the pane-bearing entries (a `>` chevron) sort to the top, reveal-only entries below,
 *  order preserved WITHIN each group. Shared by the in-app add-picker and the native Add-Property
 *  menu so both read the same. */
export function orderAddableEntries(entries: AddEntry[]): AddEntry[] {
  return [...entries.filter((e) => !e.revealOnly), ...entries.filter((e) => e.revealOnly)]
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
