import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import {
  cardMenuModel,
  type CardMenuAction,
  type CardMenuContext,
  type MoveTarget,
} from '@shared/cardMenu'

// The card's right-click menu — the page-meta items plus an Add Property ▸ submenu of the card's
// addable properties and a Move To ▸ tree of destination containers. resolve(null) covers a
// dismissed menu so the renderer no-ops.
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
    // A parent item can't itself be clicked in a native menu, so a container repeats its own
    // name as the submenu's first row (disabled when it's already the page's current parent).
    const moveNode = (t: MoveTarget): MenuItemConstructorOptions => {
      const self: MenuItemConstructorOptions = {
        label: t.label,
        enabled: t.path !== model.currentParentPath,
        click: pick(`move:${t.path}`),
      }
      if (t.children && t.children.length > 0)
        return {
          label: t.label,
          submenu: [self, { type: 'separator' }, ...t.children.map(moveNode)],
        }
      return self
    }
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
      // Move To ▸ sits directly below the opening action (Open / Open in New Tab).
      if (it.action === 'title:newtab' && model.moveTo && model.moveTo.length > 0)
        items.push({ label: 'Move To', submenu: model.moveTo.map(moveNode) })
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
