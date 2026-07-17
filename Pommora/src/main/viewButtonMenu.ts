// The ViewDropdown's right-click native menu: a dynamic Show/Hide Title toggle over a Style ▸
// Dropdown/Toolbar submenu (current values checked). Resolves the picked action to the renderer, which
// writes it through the one container-config op (view_button / view_style).
import type { BrowserWindow } from 'electron'
import type { ViewButton, ViewStyle } from '@shared/types'
import { popReturningMenu } from './returningMenu'

export type ViewButtonMenuAction = 'toggle-title' | 'style-dropdown' | 'style-toolbar'

export function popViewButtonMenu(
  win: BrowserWindow,
  current: { viewButton: ViewButton; viewStyle: ViewStyle },
): Promise<ViewButtonMenuAction | null> {
  return popReturningMenu<ViewButtonMenuAction>(win, (pick) => [
    {
      label: current.viewButton === 'labeled' ? 'Hide Title' : 'Show Title',
      click: pick('toggle-title'),
    },
    { type: 'separator' },
    {
      label: 'Style',
      submenu: [
        {
          label: 'Dropdown',
          type: 'checkbox',
          checked: current.viewStyle === 'dropdown',
          click: pick('style-dropdown'),
        },
        {
          label: 'Toolbar',
          type: 'checkbox',
          checked: current.viewStyle === 'toolbar',
          click: pick('style-toolbar'),
        },
      ],
    },
  ])
}
