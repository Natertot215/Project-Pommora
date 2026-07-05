import { EditorView } from '@codemirror/view'
import { EDITOR_ACTION_PREFIX, type FormatState } from '@shared/editorMenu'
import {
  toggleInline,
  setHeading,
  setList,
  setBlock,
  type FormatEdit,
  type InlineFormat,
  type HeadingLevel,
  type ListFormat,
  type BlockFormat
} from '../input/format'

/** Native context-menu seam — pushes editor state to main, receives chosen actions back. */
export interface EditorMenuApi {
  pushState: (s: FormatState) => void
  onAction: (cb: (action: string) => void) => () => void
}

function editFor(action: string, doc: string, from: number, to: number): FormatEdit | null {
  const [group, value] = action.split(':')
  switch (group) {
    case 'format':
      return toggleInline(doc, from, to, value as InlineFormat)
    case 'heading':
      return setHeading(doc, from, Number(value) as HeadingLevel)
    case 'list':
      return setList(doc, from, value as ListFormat)
    case 'block':
      return setBlock(doc, from, value as BlockFormat)
    default:
      return null
  }
}

/** Apply a `mdpm:*` menu action to the editor; ignores actions from other `menu:action` senders. */
export function applyEditorAction(view: EditorView, raw: string): boolean {
  if (!raw.startsWith(EDITOR_ACTION_PREFIX)) return false
  const sel = view.state.selection.main
  const edit = editFor(raw.slice(EDITOR_ACTION_PREFIX.length), view.state.doc.toString(), sel.from, sel.to)
  if (!edit) return false
  view.dispatch({
    changes: edit.changes,
    selection: edit.selection !== undefined ? { anchor: edit.selection } : undefined,
    userEvent: 'input'
  })
  view.focus()
  return true
}
