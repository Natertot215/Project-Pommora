import { styleMenuItems, type StyleMenuItem } from './columnMenu'
import type { ColumnStyle } from './columnStyles'
import { type PageMetaAction, pageMetaMenuItems } from './pageMenu'
import type { PropertyType } from './properties'
import type { ResolvedColumn } from './types'

/** The table-cell right-click menu (A-13: right-click always opens a menu, never acts).
 *  Title cells get the page meta menu; style-bearing cells get their COLUMN's Style radios;
 *  a `link` (url) cell gets Edit · Rename · Clear (its look is per-property, set in its pane, not a
 *  per-view Style); a file cell adds Edit to Style; picker-based cells add Clear (`clearable` on a
 *  styleable type, `clear-only` for select/multi/context, which carry no Style). `hideable` (cards
 *  only) appends a trailing "Remove" that drops the property from the view — `remove-only` is the
 *  bare case for a cell that would otherwise have no menu (an empty picker, a file). */
type CellMenuKind =
  | { kind: 'title'; alreadyOpen?: boolean }
  | { kind: 'style-only'; type: PropertyType; current: ColumnStyle; clearable?: boolean }
  | { kind: 'style-edit'; type: 'url' | 'file'; current: ColumnStyle }
  | { kind: 'link'; filled: boolean }
  | { kind: 'clear-only' }
  | { kind: 'remove-only' }
export type CellMenuContext = CellMenuKind & { hideable?: boolean }

export type CellMenuAction =
  | PageMetaAction
  | 'cell:edit'
  | 'cell:rename'
  | 'cell:clear'
  | 'cell:hide'
  | `style:${string}:${string}`

export interface CellMenuModel {
  items: Array<{ label: string; action: CellMenuAction; separatorBefore?: boolean }>
  /** Rendered as a `Style ▸` submenu ahead of `items` when present. */
  style?: StyleMenuItem[]
}

/** The right-click menu context for a value cell (A-13): title = page meta; url/file = the column's
 *  Style radios + Edit; status/datetime (picker-based) = Style + Clear; the inline-clearable style
 *  types (checkbox/number/last_edited_time) = Style alone; tier and select/multi/context = Clear
 *  alone. Clear is offered ONLY on a `filled` cell — a clear-only cell with no value has no menu at
 *  all, and a styleable one drops just its Clear. Anything else has no menu (null). Portable across
 *  the container views (Table cells, Cards values). */
export function cellMenuContextFor(
  col: ResolvedColumn,
  type: PropertyType | 'title' | 'tier' | undefined,
  style: ColumnStyle,
  filled: boolean,
  hideable = false,
): CellMenuContext | null {
  const base = baseCellMenu(col, type, style, filled)
  // Cards let any non-title cell drop its property (hideable): a cell that would otherwise have no menu
  // (an empty picker, a file) still gets a bare Remove; every other cell gets Remove appended below.
  if (base === null) return hideable ? { kind: 'remove-only' } : null
  return hideable ? { ...base, hideable: true } : base
}

function baseCellMenu(
  col: ResolvedColumn,
  type: PropertyType | 'title' | 'tier' | undefined,
  style: ColumnStyle,
  filled: boolean,
): CellMenuKind | null {
  if (col.kind === 'title') return { kind: 'title' }
  if (col.kind === 'tier') return filled ? { kind: 'clear-only' } : null
  if (type === 'url') return { kind: 'link', filled }
  if (type === 'file') return { kind: 'style-edit', type: 'file', current: style }
  if (type === 'status' || type === 'datetime')
    return { kind: 'style-only', type, current: style, clearable: filled }
  if (type === 'checkbox' || type === 'number' || type === 'last_edited_time') {
    return { kind: 'style-only', type, current: style }
  }
  if (type === 'select' || type === 'multi_select' || type === 'context') {
    return filled ? { kind: 'clear-only' } : null
  }
  return null
}

/** The pure per-kind item model — main maps it to Electron MenuItems. A `hideable` (card) context
 *  appends a trailing "Remove" that drops the property from the view. */
export function cellMenuModel(ctx: CellMenuContext): CellMenuModel {
  const model = baseCellMenuModel(ctx)
  if (ctx.hideable && ctx.kind !== 'title') {
    model.items = [
      ...model.items,
      {
        label: 'Remove',
        action: 'cell:hide',
        separatorBefore: model.items.length > 0 || !!model.style,
      },
    ]
  }
  return model
}

function baseCellMenuModel(ctx: CellMenuContext): CellMenuModel {
  switch (ctx.kind) {
    case 'title':
      return { items: pageMetaMenuItems(ctx.alreadyOpen) }
    case 'style-only':
      return {
        items: ctx.clearable ? [{ label: 'Clear', action: 'cell:clear' }] : [],
        style: styleMenuItems({ type: ctx.type, current: ctx.current }),
      }
    case 'style-edit':
      return {
        items: [{ label: 'Edit', action: 'cell:edit' }],
        style: styleMenuItems({ type: ctx.type, current: ctx.current }),
      }
    case 'link':
      // A URL / Link cell: Edit the URL inline; a FILLED one adds Rename (give it an alias) + Clear
      // (clear the value) — both are no-ops on an empty cell, so only Edit shows there. No per-view
      // Style — a link's look (underline / colour / full-url ⇄ title) is per-property.
      return {
        items: ctx.filled
          ? [
              { label: 'Edit', action: 'cell:edit' },
              { label: 'Rename', action: 'cell:rename' },
              { label: 'Clear', action: 'cell:clear' },
            ]
          : [{ label: 'Edit', action: 'cell:edit' }],
      }
    case 'clear-only':
      return { items: [{ label: 'Clear', action: 'cell:clear' }] }
    case 'remove-only':
      return { items: [] }
  }
}
