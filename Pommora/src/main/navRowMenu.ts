import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { NavRowMenuAction, NavRowMenuContext } from '@shared/navRowMenu'

// The NavWindow row/card menu (D-3): Open · Open in Preview · Pin/Unpin · Favorite/Unfavorite ·
// Remove, gated by the row's live state. resolve(null) covers a dismissed menu so the renderer no-ops.
export function popNavRowMenu(
  win: BrowserWindow,
  ctx: NavRowMenuContext,
): Promise<NavRowMenuAction | null> {
  return new Promise<NavRowMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: NavRowMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const items: MenuItemConstructorOptions[] = []
    if (ctx.canOpenNewTab)
      items.push({
        label: ctx.alreadyOpen ? 'Open' : 'Open in New Tab',
        click: pick('open-new-tab'),
      })
    if (ctx.isPage) items.push({ label: 'Open in Preview', click: pick('open-preview') })
    if (items.length > 0) items.push({ type: 'separator' })
    items.push({
      label: ctx.isPinned ? 'Unpin' : 'Pin',
      click: pick(ctx.isPinned ? 'unpin' : 'pin'),
    })
    items.push({
      label: ctx.isFavorite ? 'Unfavorite' : 'Favorite',
      click: pick(ctx.isFavorite ? 'unfavorite' : 'favorite'),
    })
    items.push({ type: 'separator' })
    items.push({ label: 'Remove', click: pick('remove') })

    Menu.buildFromTemplate(items).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      },
    })
  })
}
