// The editor context-menu contract. The renderer computes the editor's active formatting state
// (from CM6's EditorState — Electron's static menu params can't see it) and pushes it to main;
// main builds the native menu, reading the last pushed state at popup time. A chosen Pommora item
// dispatches a namespaced action back over the `menu:action` channel; the renderer applies the edit.

/** What the menu needs to render checkmarks/radios. Pushed renderer→main on selection/focus change. */
export interface FormatState {
  /** The CM editor (not the title/rename field) holds focus — gates the Pommora formatting submenus. */
  focused: boolean
  hasSelection: boolean
  bold: boolean
  italic: boolean
  strikethrough: boolean
  inlineCode: boolean
  link: boolean
  connection: boolean
  heading: number // 0 = paragraph, 1–6
  list: 'bullet' | 'ordered' | 'task' | null
  block: 'quote' | null
}

/** Menu-action strings (sent main→renderer), namespaced so other `menu:action` listeners ignore them. */
export const EDITOR_ACTION_PREFIX = 'mdpm:'
