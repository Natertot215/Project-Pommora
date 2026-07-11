// The view embed's two right-click menus (H-5): the title row's chrome menu (icon / title-row
// visibility) and the switcher area's presentation menu (pill titles · New View · Style) — the
// same returning-menu chassis as the ViewDropdown's. Show Title only surfaces in the area menu
// while the title row is hidden: with the row gone, its own right-click target is gone too.
import type { BrowserWindow } from 'electron'
import type { ViewButton, ViewStyle } from '@shared/types'
import { popReturningMenu } from './returningMenu'

export type EmbedTitleMenuAction = 'toggle-icon' | 'hide-title'

export function popEmbedTitleMenu(win: BrowserWindow, iconShown: boolean): Promise<EmbedTitleMenuAction | null> {
  return popReturningMenu<EmbedTitleMenuAction>(win, (pick) => [
    { label: iconShown ? 'Hide Icon' : 'Show Icon', click: pick('toggle-icon') },
    { label: 'Hide Title', click: pick('hide-title') }
  ])
}

export type EmbedAreaMenuAction = 'toggle-pill-titles' | 'show-title' | 'new-view' | 'style-dropdown' | 'style-toolbar'

export function popEmbedAreaMenu(
  win: BrowserWindow,
  current: { viewButton: ViewButton; viewStyle: ViewStyle; titleShown: boolean }
): Promise<EmbedAreaMenuAction | null> {
  return popReturningMenu<EmbedAreaMenuAction>(win, (pick) => [
    { label: current.viewButton === 'labeled' ? 'Hide Titles' : 'Show Titles', click: pick('toggle-pill-titles') },
    ...(current.titleShown ? [] : [{ label: 'Show Title', click: pick('show-title') }]),
    { label: 'New View', click: pick('new-view') },
    { type: 'separator' as const },
    {
      label: 'Style',
      submenu: [
        { label: 'Dropdown', type: 'checkbox' as const, checked: current.viewStyle === 'dropdown', click: pick('style-dropdown') },
        { label: 'Toolbar', type: 'checkbox' as const, checked: current.viewStyle === 'toolbar', click: pick('style-toolbar') }
      ]
    }
  ])
}
