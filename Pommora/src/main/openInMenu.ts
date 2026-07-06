// The Configuration "Open In" control's native menu (macOS) — Full Page / Preview, current checked.
// The non-mac path uses the glass PickerMenu; both write the picked value the same way. Collection-
// owned (a Set proxies its parent Collection's value).
import type { BrowserWindow } from 'electron'
import type { OpenIn } from '@shared/types'
import { popReturningMenu } from './returningMenu'

export function popOpenInMenu(win: BrowserWindow, current: OpenIn): Promise<OpenIn | null> {
  return popReturningMenu<OpenIn>(win, (pick) => [
    { label: 'Full Page', type: 'checkbox', checked: current !== 'page-preview', click: pick('full-page') },
    { label: 'Preview', type: 'checkbox', checked: current === 'page-preview', click: pick('page-preview') }
  ])
}
