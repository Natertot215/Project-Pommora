import { Menu } from 'electron'
import type { BrowserWindow } from 'electron'
import type { ColumnMenuAction } from '@shared/columnMenu'

// The table-view column header's right-click menu — same shape as popCalloutMenu. One item today
// (hide the column); resolve(null) covers a dismissed menu so the renderer no-ops.
export function popColumnMenu(win: BrowserWindow): Promise<ColumnMenuAction | null> {
  return new Promise<ColumnMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: ColumnMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const menu = Menu.buildFromTemplate([{ label: 'Hide Property', click: pick('column:hide') }])
    menu.popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
