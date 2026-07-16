import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { TabMenuAction, TabMenuContext } from '@shared/tabMenu'

// The tab right-click menu (I-12): Pin/Unpin · Close, gated by the tab's state.
// resolve(null) covers a dismissed menu so the renderer no-ops.
export function popTabMenu(win: BrowserWindow, ctx: TabMenuContext): Promise<TabMenuAction | null> {
  return new Promise<TabMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: TabMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const items: MenuItemConstructorOptions[] = []
    if (!ctx.isNewTab) items.push({ label: ctx.pinned ? 'Unpin' : 'Pin', click: pick(ctx.pinned ? 'unpin' : 'pin') })
    if (!ctx.pinned) {
      if (items.length > 0) items.push({ type: 'separator' })
      items.push({ label: 'Close', click: pick('close') })
    }
    if (items.length === 0) {
      resolve(null)
      return
    }
    Menu.buildFromTemplate(items).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
