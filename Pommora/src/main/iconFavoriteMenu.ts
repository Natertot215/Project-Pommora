import { Menu } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'

/** The icon picker's right-click menu — a single Favorite/Remove toggle. Resolves 'toggle' on click,
 *  null on dismiss; the renderer owns the favorites write (personalization). */
export function popIconFavoriteMenu(
  win: BrowserWindow,
  favorited: boolean,
): Promise<'toggle' | null> {
  return new Promise<'toggle' | null>((resolve) => {
    let acted = false
    const items: MenuItemConstructorOptions[] = [
      {
        label: favorited ? 'Remove from Favorites' : 'Favorite',
        click: () => {
          acted = true
          resolve('toggle')
        },
      },
    ]
    Menu.buildFromTemplate(items).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      },
    })
  })
}
