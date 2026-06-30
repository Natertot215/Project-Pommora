import type { SelectionState } from '@shared/types'

/**
 * What the in-window content view exposes to the Settings dropdown — the React mirror of Swift's
 * ViewSettingsScope. The toolbar's Settings button is generic chrome; this maps the current
 * selection to a scope, and SettingsDropdown switches on it to pick the pane (or show nothing).
 * Adding a future surface's pane is a new case here + a switch arm there, never a change to the button.
 */
export type ViewSettingsScope = 'view' | 'page' | 'context' | 'none'

export function viewSettingsScope(selection: SelectionState): ViewSettingsScope {
  switch (selection.kind) {
    case 'collection':
    case 'set':
      return 'view'
    case 'page':
      return 'page'
    case 'context':
      return 'context'
    default:
      return 'none'
  }
}
