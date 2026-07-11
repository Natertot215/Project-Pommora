// The page-picker drill menu for embeds (G-9's Page flow, native-menu form): the
// renderer builds the item tree (main has no NexusTree) — Collections drill into
// their pages and Sets. Returning-picker: resolves the picked page id, null on dismiss.
import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { PagePickerItem } from '@shared/blocks'

export function popPagePickerMenu(win: BrowserWindow, items: PagePickerItem[]): Promise<string | null> {
  return new Promise((resolve) => {
    let acted = false
    const toTemplate = (nodes: PagePickerItem[]): MenuItemConstructorOptions[] =>
      nodes.map((n) =>
        n.submenu
          ? { label: n.label, submenu: toTemplate(n.submenu), enabled: n.submenu.length > 0 }
          : {
              label: n.label,
              enabled: typeof n.pageId === 'string',
              click: () => {
                acted = true
                resolve(n.pageId ?? null)
              }
            }
      )
    Menu.buildFromTemplate(toTemplate(items)).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
