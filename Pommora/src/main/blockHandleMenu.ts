// The block drag-handle menu (B-6/G-8): Type ▸ / Style ▸ / Remove. Returning-picker —
// the renderer performs the write. Remove confirms here in main first (the property/
// option-menu convention); Type entries wait disabled until the embed pickers ship.
import { dialog, Menu } from 'electron'
import type { BrowserWindow } from 'electron'
import type { BlockHandleMenuAction, BlockStyle } from '@shared/blocks'

export function popBlockHandleMenu(win: BrowserWindow, opts: { style: BlockStyle }): Promise<BlockHandleMenuAction | null> {
  return new Promise((resolve) => {
    let acted = false
    const pick = (action: BlockHandleMenuAction) => () => {
      acted = true
      resolve(action)
    }
    Menu.buildFromTemplate([
      {
        label: 'Type',
        submenu: [
          { label: 'View', enabled: false, click: pick('type:view') },
          { label: 'Page', click: pick('type:page') }
        ]
      },
      {
        label: 'Style',
        submenu: [
          { label: 'Bordered', type: 'radio', checked: opts.style === 'bordered', click: pick('style:bordered') },
          { label: 'Borderless', type: 'radio', checked: opts.style === 'borderless', click: pick('style:borderless') }
        ]
      },
      { type: 'separator' },
      {
        label: 'Remove',
        click: async () => {
          acted = true
          const { response } = await dialog.showMessageBox(win, {
            type: 'warning',
            buttons: ['Remove', 'Cancel'],
            defaultId: 0,
            cancelId: 1,
            message: 'Remove this block?',
            detail: 'A markdown block’s file moves to the nexus’s .trash (recoverable); embeds only remove the tile.'
          })
          resolve(response === 0 ? 'remove' : null)
        }
      }
    ]).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
