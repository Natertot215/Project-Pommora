import { styleMenuItems, type StyleMenuItem } from './columnMenu'
import type { ColumnStyle } from './columnStyles'
import type { PropertyType } from './properties'

/** The table-cell right-click menu (A-13: right-click always opens a menu, never acts).
 *  Title cells get the page meta menu; style-bearing cells get their COLUMN's Style radios;
 *  a `link` (url) cell gets Edit · Rename · Remove (its look is per-property, set in its pane, not a
 *  per-view Style); a file cell adds Edit to Style; picker-based cells add Clear (`clearable` on a
 *  styleable type, `clear-only` for select/multi/context, which carry no Style). */
export type CellMenuContext =
  | { kind: 'title' }
  | { kind: 'style-only'; type: PropertyType; current: ColumnStyle; clearable?: boolean }
  | { kind: 'style-edit'; type: 'url' | 'file'; current: ColumnStyle }
  | { kind: 'link' }
  | { kind: 'clear-only' }

export type CellMenuAction =
  | 'title:rename'
  | 'title:icon'
  | 'title:delete'
  | 'cell:edit'
  | 'cell:rename'
  | 'cell:clear'
  | `style:${string}:${string}`

export interface CellMenuModel {
  items: Array<{ label: string; action: CellMenuAction; separatorBefore?: boolean }>
  /** Rendered as a `Style ▸` submenu ahead of `items` when present. */
  style?: StyleMenuItem[]
}

/** The pure per-kind item model — main maps it to Electron MenuItems. */
export function cellMenuModel(ctx: CellMenuContext): CellMenuModel {
  switch (ctx.kind) {
    case 'title':
      return {
        items: [
          { label: 'Rename', action: 'title:rename' },
          { label: 'Change Icon', action: 'title:icon' },
          { label: 'Delete', action: 'title:delete', separatorBefore: true }
        ]
      }
    case 'style-only':
      return {
        items: ctx.clearable ? [{ label: 'Clear', action: 'cell:clear' }] : [],
        style: styleMenuItems({ type: ctx.type, current: ctx.current })
      }
    case 'style-edit':
      return {
        items: [{ label: 'Edit', action: 'cell:edit' }],
        style: styleMenuItems({ type: ctx.type, current: ctx.current })
      }
    case 'link':
      // A URL / Link cell: Edit the URL inline, Rename to give it an alias, Remove the value. No
      // per-view Style — a link's look (underline / colour / full-url ⇄ title) is per-property.
      return {
        items: [
          { label: 'Edit', action: 'cell:edit' },
          { label: 'Rename', action: 'cell:rename' },
          { label: 'Remove', action: 'cell:clear' }
        ]
      }
    case 'clear-only':
      return { items: [{ label: 'Clear', action: 'cell:clear' }] }
  }
}
