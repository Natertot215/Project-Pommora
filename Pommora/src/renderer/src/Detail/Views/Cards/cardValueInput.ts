import { isValidLink, normalizeLinkUrl } from '@shared/links'
import type { PropertyDefinition, PropertyType } from '@shared/properties'
import { isBlankValue, type PropertyValue } from '@shared/propertyValue'
import type { NexusLabels, ResolvedColumn, ViewRow } from '@shared/types'
import { isCompact, type SavedView } from '@shared/views'
import { hiddenListIds } from '@renderer/Components/Detail/hiddenPaneModel'
import { resolveFieldValue } from '../pipeline/value'
import { columnLabel, TIER_LEVEL_BY_ID } from '../Table/columnLabel'
import type { ResolveContext } from '../Table/resolveContext'
import { serializeLink } from '../Table/linkValue'

/** The kinds whose BLANK entries drill into a value pane. Checkbox is deliberately excluded from the
 *  pane split (its box on the card is the toggle — an add-list pick just reveals it); tiers/contexts
 *  pane via contextOptions rather than this set. */
export const ADDABLE_TYPES: ReadonlySet<string> = new Set([
  'select',
  'status',
  'multi_select',
  'datetime',
  'number',
  'url',
  'checkbox',
])

/** The card's VISIBLE property columns. Standard keeps a blank one as a labeled, fillable row;
 *  Compact's label-less flow can't render an empty value, so it drops blanks — EXCEPT a checkbox,
 *  whose (unchecked) box is the on-card toggle. */
export function shownColumnsFor(
  row: ViewRow,
  columns: ResolvedColumn[],
  ctx: ResolveContext,
  compactLayout: boolean,
): ResolvedColumn[] {
  return columns.filter(
    (c) =>
      c.kind !== 'title' &&
      (!compactLayout ||
        !isBlankValue(resolveFieldValue(row, c.id, ctx.schema)) ||
        ctx.schema.find((d) => d.id === c.id)?.type === 'checkbox'),
  )
}

/** The add menu: everything NOT currently shown — the Visibility hidden list, any schema prop that's
 *  revealed-but-blank (Compact drops it, so it stays addable to re-fill), and Compact-suppressed blank
 *  tiers. Context-shaped entries pane when blank (the picker fills in place); filled entries reveal. */
export function addEntriesFor(
  row: ViewRow,
  view: SavedView,
  ctx: ResolveContext,
  labels: NexusLabels,
  columns: ResolvedColumn[],
): AddEntry[] {
  const shownIds = new Set(shownColumnsFor(row, columns, ctx, isCompact(view)).map((c) => c.id))
  const bySchema = new Map(ctx.schema.map((d) => [d.id, d]))
  const ids = [
    ...new Set([
      ...hiddenListIds(view, ctx.schema),
      ...ctx.schema.map((d) => d.id),
      ...columns.filter((c) => c.kind === 'tier').map((c) => c.id),
    ]),
  ]
  return ids
    .filter((id) => !shownIds.has(id))
    .map((id) => {
      const def = bySchema.get(id) ?? null
      const type = def?.type ?? 'context'
      const blank = isBlankValue(resolveFieldValue(row, id, ctx.schema))
      const contextShaped = TIER_LEVEL_BY_ID[id] !== undefined || type === 'context'
      const revealOnly = contextShaped
        ? !blank
        : !def || !ADDABLE_TYPES.has(type) || type === 'checkbox' || !blank
      return { id, name: columnLabel(id, ctx.schema, labels), type, def, revealOnly }
    })
}

/** An add-menu entry's column ref: a reserved tier id routes as a TIER (writeTierValue), everything
 *  else as a property — the same split commitValue makes for on-card values. */
export const addColumn = (id: string): ResolvedColumn => ({
  id,
  kind: TIER_LEVEL_BY_ID[id] !== undefined ? 'tier' : 'property',
})

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
