import { Menu, dialog } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import {
  propertyMenuModel,
  type PropertyMenuAction,
  type PropertyMenuContext,
} from '@shared/propertyMenu'

/** Pop the property menu natively (the popCellMenu promise shape). `property:destroy` runs its
 *  confirm dialog HERE and resolves only on confirm — the renderer never sees an unconfirmed
 *  destroy. resolve(null) covers a dismissed menu or a cancelled confirm. */
export function popPropertyMenu(
  win: BrowserWindow,
  ctx: PropertyMenuContext,
): Promise<PropertyMenuAction | null> {
  return new Promise<PropertyMenuAction | null>((resolve) => {
    let acted = false
    const items: MenuItemConstructorOptions[] = []
    for (const it of propertyMenuModel(ctx)) {
      if (it.destructive) items.push({ type: 'separator' })
      items.push({
        label: it.label,
        click: async () => {
          acted = true
          if (it.action !== 'property:destroy') {
            resolve(it.action)
            return
          }
          const { response } = await dialog.showMessageBox(win, {
            type: 'warning',
            buttons: ['Delete', 'Cancel'],
            defaultId: 0,
            cancelId: 1,
            message: `Delete “${ctx.name}” everywhere?`,
            detail:
              'It is removed from every collection; a recovery snapshot lands in the nexus’s .trash folder.',
          })
          resolve(response === 0 ? 'property:destroy' : null)
        },
      })
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
