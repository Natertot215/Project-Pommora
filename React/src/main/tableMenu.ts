import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { TableMenuAction, TableMenuContext } from '@shared/tableMenu'

function itemsFor(
  ctx: TableMenuContext,
  pick: (a: TableMenuAction) => () => void
): MenuItemConstructorOptions[] {
  if (ctx.kind === 'header') {
    return [{ label: 'Delete Table', click: pick('table:delete') }]
  }
  if (ctx.kind === 'row') {
    return [
      { label: 'Insert Row Above', click: pick('row:insert-above') },
      { label: 'Insert Row Below', click: pick('row:insert-below') },
      { type: 'separator' },
      { label: 'Clear', click: pick('row:clear') },
      { label: 'Delete', click: pick('row:delete') }
    ]
  }
  const align = (label: string, a: 'left' | 'center' | 'right'): MenuItemConstructorOptions => ({
    label,
    type: 'radio',
    checked: ctx.align === a,
    click: pick(`align:${a}`)
  })
  return [
    { label: 'Align', submenu: [align('Left', 'left'), align('Center', 'center'), align('Right', 'right')] },
    { type: 'separator' },
    { label: 'Insert Column Left', click: pick('col:insert-left') },
    { label: 'Insert Column Right', click: pick('col:insert-right') },
    { type: 'separator' },
    { label: 'Clear', click: pick('col:clear') },
    { label: 'Delete', click: pick('col:delete') }
  ]
}

export function popTableMenu(win: BrowserWindow, ctx: TableMenuContext): Promise<TableMenuAction | null> {
  return new Promise<TableMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: TableMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const menu = Menu.buildFromTemplate(itemsFor(ctx, pick))
    menu.popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
