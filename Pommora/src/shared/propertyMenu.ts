/** The Properties pane's native menus (A-8/A-10). The editor's ⋮ carries Remove AND Delete —
 *  Delete is deliberately reachable ONLY inside the property's own pane, behind main's confirm
 *  dialog. An assigned row right-clicks to Rename · Remove; a registry row to Rename only
 *  (Remove is meaningless unassigned). Pure model — main maps it to Electron MenuItems. */

export type PropertyMenuContext =
  | { kind: 'editor'; name: string }
  | { kind: 'assigned-row'; name: string }
  | { kind: 'registry-row'; name: string }

export type PropertyMenuAction = 'property:rename' | 'property:remove' | 'property:destroy'

export interface PropertyMenuItem {
  label: string
  action: PropertyMenuAction
  /** Main separates a destructive item from the rest and gates it behind the confirm dialog. */
  destructive?: boolean
}

export function propertyMenuModel(ctx: PropertyMenuContext): PropertyMenuItem[] {
  switch (ctx.kind) {
    case 'editor':
      return [
        { label: 'Remove', action: 'property:remove' },
        { label: 'Delete', action: 'property:destroy', destructive: true },
      ]
    case 'assigned-row':
      return [
        { label: 'Rename', action: 'property:rename' },
        { label: 'Remove', action: 'property:remove' },
      ]
    case 'registry-row':
      return [{ label: 'Rename', action: 'property:rename' }]
  }
}
