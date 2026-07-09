// Generic native value-pick menu (the Grouping pane footings) — a radio list over labels,
// resolving the picked label or null on dismiss. One handler for every label-valued footing;
// a control with typed values (like Open In) keeps its own dedicated menu.
import type { BrowserWindow } from 'electron'
import { popReturningMenu } from './returningMenu'

export function popValueMenu(win: BrowserWindow, options: string[], current: string): Promise<string | null> {
  return popReturningMenu<string>(win, (pick) =>
    options.map((label) => ({ label, type: 'radio' as const, checked: label === current, click: pick(label) }))
  )
}
