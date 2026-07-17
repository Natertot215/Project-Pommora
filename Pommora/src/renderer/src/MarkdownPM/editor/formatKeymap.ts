import { keymap, type KeyBinding } from '@codemirror/view'
import { EDITOR_ACTION_PREFIX } from '@shared/editorMenu'
import { applyEditorAction } from './menu'

// Formatting shortcuts reuse the same transforms the context menu dispatches (one source of truth).
// `Mod` = ⌘ on macOS, Ctrl elsewhere. Context-menu accelerators only display these — the keys live here.
const bind = (key: string, action: string): KeyBinding => ({
  key,
  run: (view) => applyEditorAction(view, EDITOR_ACTION_PREFIX + action),
})

export const formatKeymap = keymap.of([
  bind('Mod-b', 'format:bold'),
  bind('Mod-i', 'format:italic'),
  bind('Mod-Shift-x', 'format:strikethrough'),
  // Inline Code has no keybinding — ⌘E belongs to the ribbon toggle (settings.json commands).
  bind('Mod-k', 'format:link'),
  bind('Mod-Shift-k', 'format:connection'),
])
