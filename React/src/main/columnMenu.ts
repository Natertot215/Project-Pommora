import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { ColumnMenuAction, ColumnMenuContext } from '@shared/columnMenu'
import type { ColumnAlign } from '@shared/views'

// The table-view column header's right-click menu (E-1/E-5) — same shape as popTableMenu. Align (a radio
// L/C/R, current checked) + Hide; the Title column carries neither (empty menu ⇒ dismissed). resolve(null)
// covers a dismissed menu so the renderer no-ops.
export function popColumnMenu(win: BrowserWindow, ctx: ColumnMenuContext): Promise<ColumnMenuAction | null> {
  return new Promise<ColumnMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: ColumnMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const align = (label: string, a: ColumnAlign): MenuItemConstructorOptions => ({
      label,
      type: 'radio',
      checked: ctx.align === a,
      click: pick(`align:${a}`)
    })
    const items: MenuItemConstructorOptions[] = []
    if (ctx.alignable) {
      items.push({ label: 'Align', submenu: [align('Left', 'left'), align('Center', 'center'), align('Right', 'right')] })
    }
    if (ctx.alignable && ctx.hideable) items.push({ type: 'separator' })
    if (ctx.hideable) items.push({ label: 'Hide', click: pick('column:hide') })
    if (items.length === 0) {
      resolve(null)
      return
    }
    const menu = Menu.buildFromTemplate(items)
    menu.popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
