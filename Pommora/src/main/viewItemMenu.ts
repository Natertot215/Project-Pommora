// The ViewSettings ⋮ menu — Duplicate / Delete. Delete is disabled on a container's only view (and the
// sentinel), matching deleteView's refuse-last rule. Returning-picker: resolves the action, the
// renderer performs it.
import type { BrowserWindow } from 'electron'
import { popReturningMenu } from './returningMenu'

export type ViewItemMenuAction = 'view:duplicate' | 'view:delete'

export function popViewItemMenu(win: BrowserWindow, opts: { canDelete: boolean }): Promise<ViewItemMenuAction | null> {
  return popReturningMenu<ViewItemMenuAction>(win, (pick) => [
    { label: 'Duplicate', click: pick('view:duplicate') },
    { type: 'separator' },
    { label: 'Delete', enabled: opts.canDelete, click: pick('view:delete') }
  ])
}
