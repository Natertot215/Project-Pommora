import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { ConnMenuAction } from '@shared/connections'

// The wikilink right-click menu — popCellMenu's shape: main pops at the cursor, resolves the chosen
// action; resolve(null) covers a dismissed menu so the renderer no-ops.
export function popConnMenu(win: BrowserWindow): Promise<ConnMenuAction | null> {
  return new Promise<ConnMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: ConnMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const items: MenuItemConstructorOptions[] = [
      { label: 'Open in Preview', click: pick('preview') },
    ]
    Menu.buildFromTemplate(items).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      },
    })
  })
}
