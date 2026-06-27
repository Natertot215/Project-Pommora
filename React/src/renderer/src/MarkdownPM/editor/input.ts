import { EditorView, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import {
  continueListOnEnter,
  continueBlockquoteOnEnter,
  smartBackspace,
  canonicalizeCheckbox,
  autoPair,
  autoDelete,
  closeConstructOnEnter,
  closeConstructOnShiftEnter,
  dashArrow,
  calloutShorthand,
  shiftEnterEdit,
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
  // Close an open construct before list/blockquote continuation, so a caret inside a pair jumps past its closer.
  return apply(
    view,
    closeConstructOnEnter(doc, s.from, s.to) ??
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

// Shift+Enter exits a construct (plain newline) — except inside a callout, where it stays in the box. If the
// caret sits inside an unclosed pair, it closes that first so the break never lands inside the pair.
const onShiftEnter = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = view.state.doc.toString()
  return apply(view, closeConstructOnShiftEnter(doc, s.from, s.to) ?? shiftEnterEdit(doc, s.from, s.to))
}

export const markdownInput = [
  Prec.high(
    keymap.of([
      { key: 'Enter', run: onEnter },
      { key: 'Shift-Enter', run: onShiftEnter },
      { key: 'Tab', run: onTab },
      { key: 'Backspace', run: onBackspace },
      // Shift+Backspace ("Shift+Delete" on Mac) joins like Backspace inside a callout instead of falling to the
      // default delete, which would erode the body prefix; the guard backstops every other delete combo.
      { key: 'Shift-Backspace', run: onBackspace }
    ])
  ),
  EditorView.inputHandler.of((view, from, to, text) => {
    if (text.length !== 1 || from !== to) return false // single-char inserts only; paste/IME pass through
    const doc = view.state.doc.toString()
    return apply(
      view,
      calloutShorthand(doc, from, from, text) ??
        canonicalizeCheckbox(doc, from, from, text) ??
        autoPair(doc, from, from, text) ??
        dashArrow(doc, from, from, text)
    )
  })
]
