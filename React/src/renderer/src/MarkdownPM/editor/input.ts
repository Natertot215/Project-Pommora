import { EditorView, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import {
  continueListOnEnter,
  continueBlockquoteOnEnter,
  smartBackspace,
  canonicalizeCheckbox,
  autoPair,
  autoDelete,
  bracketSkipOnEnter,
  dashArrow,
  indentListOnTab,
  type Edit
} from '../input'

function apply(view: EditorView, edit: Edit | null): boolean {
  if (!edit) return false
  view.dispatch({
    changes: { from: edit.from, to: edit.to, insert: edit.insert },
    selection: { anchor: edit.selection },
    scrollIntoView: true,
    userEvent: 'input'
  })
  return true
}

const onEnter = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = view.state.doc.toString()
  // Bracket-skip before list/blockquote continuation, so a caret between an empty pair jumps.
  return apply(
    view,
    bracketSkipOnEnter(doc, s.from, s.to) ??
      continueListOnEnter(doc, s.from, s.to) ??
      continueBlockquoteOnEnter(doc, s.from, s.to)
  )
}

const onBackspace = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = view.state.doc.toString()
  return apply(view, smartBackspace(doc, s.from, s.to) ?? autoDelete(doc, s.from, s.to))
}

// Always returns true so Tab never escapes the editor to focus the sidebar.
const onTab = (view: EditorView): boolean => {
  const s = view.state.selection.main
  apply(view, indentListOnTab(view.state.doc.toString(), s.from, s.to))
  return true
}

// Shift+Enter is the construct exit: a plain newline, never a list/blockquote continue.
const onShiftEnter = (view: EditorView): boolean => {
  const s = view.state.selection.main
  view.dispatch({ changes: { from: s.from, to: s.to, insert: '\n' }, selection: { anchor: s.from + 1 }, userEvent: 'input' })
  return true
}

export const markdownInput = [
  Prec.high(
    keymap.of([
      { key: 'Enter', run: onEnter },
      { key: 'Shift-Enter', run: onShiftEnter },
      { key: 'Tab', run: onTab },
      { key: 'Backspace', run: onBackspace }
    ])
  ),
  EditorView.inputHandler.of((view, from, to, text) => {
    if (text.length !== 1 || from !== to) return false // single-char inserts only; paste/IME pass through
    const doc = view.state.doc.toString()
    return apply(
      view,
      canonicalizeCheckbox(doc, from, from, text) ?? autoPair(doc, from, from, text) ?? dashArrow(doc, from, from, text)
    )
  })
]
