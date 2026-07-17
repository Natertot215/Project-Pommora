import { Menu } from 'electron'
import type { BrowserWindow } from 'electron'
import type { CalloutMenuAction } from '@shared/calloutMenu'

// The callout grip's right-click menu — same shape as popTableMenu. One item today; the resolve(null)
// path covers a dismissed menu so the renderer can no-op.
export function popCalloutMenu(win: BrowserWindow): Promise<CalloutMenuAction | null> {
  return new Promise<CalloutMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: CalloutMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const menu = Menu.buildFromTemplate([
      { label: 'Delete Callout', click: pick('callout:delete') },
    ])
    menu.popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      },
    })
  })
}
