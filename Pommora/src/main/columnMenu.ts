import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import { styleMenuItems, type ColumnMenuAction, type ColumnMenuContext } from '@shared/columnMenu'
import type { ColumnAlign } from '@shared/views'
import { styleSubmenu } from './styleMenu'

// The table-view column header's right-click menu (E-1/E-5) — same shape as popTableMenu. Align (a radio
// L/C/R, current checked) + Style (per-type radios from the shared builder) + Hide; the Title column
// carries none (empty menu ⇒ dismissed). resolve(null) covers a dismissed menu so the renderer no-ops.
export function popColumnMenu(
  win: BrowserWindow,
  ctx: ColumnMenuContext,
): Promise<ColumnMenuAction | null> {
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
      click: pick(`align:${a}`),
    })
    const items: MenuItemConstructorOptions[] = []
    if (ctx.alignable) {
      items.push({
        label: 'Align',
        submenu: [align('Left', 'left'), align('Center', 'center'), align('Right', 'right')],
      })
    }
    const styleRows = ctx.style ? styleMenuItems(ctx.style) : []
    if (styleRows.length > 0) {
      items.push({ label: 'Style', submenu: styleSubmenu(styleRows, pick) })
    }
    if (ctx.iconsShown !== undefined) {
      items.push({
        label: 'Icon',
        type: 'checkbox',
        checked: ctx.iconsShown,
        click: pick('column:toggle-icons'),
      })
    }
    const hasTop = ctx.alignable || styleRows.length > 0 || ctx.iconsShown !== undefined
    if (hasTop && ctx.hideable) items.push({ type: 'separator' })
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
      },
    })
  })
}
