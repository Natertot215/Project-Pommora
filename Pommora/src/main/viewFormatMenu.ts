// The ViewSettings Format control's native menu (macOS) — Standard / Compact, current value checked.
// The non-mac path uses the glass PickerMenu (renderer); both write the picked format the same way.
import type { BrowserWindow } from 'electron'
import type { ViewFormat } from '@shared/views'
import { popReturningMenu } from './returningMenu'

export function popViewFormatMenu(
  win: BrowserWindow,
  current: ViewFormat,
): Promise<ViewFormat | null> {
  return popReturningMenu<ViewFormat>(win, (pick) => [
    {
      label: 'Standard',
      type: 'checkbox',
      checked: current !== 'compact',
      click: pick('standard'),
    },
    { label: 'Compact', type: 'checkbox', checked: current === 'compact', click: pick('compact') },
  ])
}
