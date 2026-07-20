import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import { cardMenuModel, type CardMenuAction, type CardMenuContext } from '@shared/cardMenu'

// The card's right-click menu — the page-meta items plus an Add Property ▸ submenu of the card's
// addable properties. resolve(null) covers a dismissed menu so the renderer no-ops.
export function popCardMenu(
  win: BrowserWindow,
  ctx: CardMenuContext,
): Promise<CardMenuAction | null> {
  return new Promise<CardMenuAction | null>((resolve) => {
    let acted = false
    const pick = (a: CardMenuAction) => (): void => {
      acted = true
      resolve(a)
    }
    const model = cardMenuModel(ctx)
    const items: MenuItemConstructorOptions[] = []
    if (model.addProperty && model.addProperty.length > 0) {
      items.push({
        label: 'Add Property',
        submenu: model.addProperty.map((a) => ({ label: a.label, click: pick(a.action) })),
      })
    }
    const hasAddProperty = items.length > 0
    model.items.forEach((it, i) => {
      if (it.separatorBefore || (i === 0 && hasAddProperty)) items.push({ type: 'separator' })
      items.push({ label: it.label, click: pick(it.action) })
    })
    const menu = Menu.buildFromTemplate(items)
    menu.popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      },
    })
  })
}
