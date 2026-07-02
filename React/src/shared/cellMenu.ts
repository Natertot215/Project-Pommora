import { styleMenuItems, type StyleMenuItem } from './columnMenu'
import type { ColumnStyle } from './columnStyles'
import type { PropertyType } from './properties'

/** The table-cell right-click menu (A-13: right-click always opens a menu, never acts).
 *  Title cells get the page meta menu; style-bearing cells get their COLUMN's Style radios;
 *  link/file cells add Edit. Select/multi cells pop NO menu — the renderer never builds a
 *  context for them. */
export type CellMenuContext =
  | { kind: 'title' }
  | { kind: 'style-only'; type: PropertyType; current: ColumnStyle }
  | { kind: 'style-edit'; type: 'url' | 'file'; current: ColumnStyle }

export type CellMenuAction = 'title:rename' | 'title:icon' | 'title:delete' | 'cell:edit' | `style:${string}:${string}`

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
      return { items: [], style: styleMenuItems({ type: ctx.type, current: ctx.current }) }
    case 'style-edit':
      return {
        items: [{ label: 'Edit', action: 'cell:edit' }],
        style: styleMenuItems({ type: ctx.type, current: ctx.current })
      }
  }
}
