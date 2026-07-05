/** The option chip's native right-click menu (Planning 7-3, Phase 2). Rename edits inline; Remove
 *  deletes the option AND strips its value from every page; Clear strips the value but keeps the
 *  option. Remove and Clear are destructive — main pops a confirm and resolves only on confirm, so
 *  the renderer never runs an unconfirmed strip. Pure model — main maps it to Electron MenuItems. */

export interface OptionMenuContext {
  name: string
}

export type OptionMenuAction = 'option:rename' | 'option:remove' | 'option:clear'

export interface OptionMenuItem {
  label: string
  action: OptionMenuAction
  /** Main gates the action behind a confirm dialog (Remove / Clear). */
  confirm?: boolean
}

export function optionMenuModel(): OptionMenuItem[] {
  return [
    { label: 'Rename', action: 'option:rename' },
    { label: 'Remove', action: 'option:remove', confirm: true },
    { label: 'Clear', action: 'option:clear', confirm: true }
  ]
}
