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
  // The first column can read like the header row (a Pommora-only visual; the .md stays a plain table).
  // Checkbox carries the on/off state; the label reads "Heading Column" (✓) when on, "Make …" when off.
  const heading: MenuItemConstructorOptions[] =
    ctx.index === 0
      ? [
          {
            label: ctx.headingColumn ? 'Heading Column' : 'Make Heading Column',
            type: 'checkbox',
            checked: ctx.headingColumn ?? false,
            click: pick('col:toggle-heading')
          }
        ]
      : []
  return [
    { label: 'Align', submenu: [align('Left', 'left'), align('Center', 'center'), align('Right', 'right')] },
    { type: 'separator' },
    ...heading,
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
