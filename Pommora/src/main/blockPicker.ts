// The native returning drill menu the embed pickers share (G-9's interim form, until
// the G-16 PickerMenu component lands): the renderer builds the item tree (main has
// no NexusTree); resolves the pick, null on dismiss.
import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import type { DrillPickItem } from '@shared/blocks'

export function popDrillMenu<T>(win: BrowserWindow, items: Array<DrillPickItem<T>>): Promise<T | null> {
  return new Promise((resolve) => {
    let acted = false
    const toTemplate = (nodes: Array<DrillPickItem<T>>): MenuItemConstructorOptions[] =>
      nodes.map((n) =>
        n.separator
          ? { type: 'separator' as const }
          : n.submenu
            ? { label: n.label, submenu: toTemplate(n.submenu), enabled: n.submenu.length > 0 }
            : {
                label: n.label,
                enabled: n.pick !== undefined,
                click: () => {
                  acted = true
                  resolve(n.pick ?? null)
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
