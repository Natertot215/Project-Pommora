// The returning-picker menu plumbing: pop a native menu, resolve the chosen action BACK to the
// renderer (which performs the write), and resolve null when the menu is dismissed. The single home
// for the `let acted` / popup-callback dance that the option/property/cell/column/table/callout menus
// each hand-roll today; new menus (view-button, view-item, view-format) declare only their template.
import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'

/** `buildItems` receives `pick`, a factory turning an action into a click handler that resolves it. */
export function popReturningMenu<A>(
  win: BrowserWindow,
  buildItems: (pick: (action: A) => () => void) => MenuItemConstructorOptions[]
): Promise<A | null> {
  return new Promise((resolve) => {
    let acted = false
    const pick = (action: A) => () => {
      acted = true
      resolve(action)
    }
    Menu.buildFromTemplate(buildItems(pick)).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
