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
  outdentListOnShiftTab,
  type Edit,
} from '../input'
import { tableRegions } from '../Tables/regions'
import { docString } from './docCache'

function apply(view: EditorView, edit: Edit | null): boolean {
  if (!edit) return false
  view.dispatch({
    changes: { from: edit.from, to: edit.to, insert: edit.insert },
    selection: { anchor: edit.selection },
    scrollIntoView: true,
    userEvent: 'input',
  })
  return true
}

// Enter at a table's bottom boundary lays a blank-line fence: a bare `\n` would put the caret on a line
// touching the table, and GFM lazy continuation absorbs any non-blank line there as a table row — typed
// prose would join the table character by character.
const tableBoundaryEnter = (doc: string, s: { from: number; to: number }): Edit | null => {
  if (s.from !== s.to) return null
  const r = tableRegions(doc).find((r) => r.to === s.from)
  return r ? { from: s.from, to: s.from, insert: '\n\n', selection: s.from + 2 } : null
}

const onEnter = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = docString(view.state.doc)
  // Close an open construct before list/blockquote continuation, so a caret inside a pair jumps past its closer.
  return apply(
    view,
    closeConstructOnEnter(doc, s.from, s.to) ??
      tableBoundaryEnter(doc, s) ??
      continueListOnEnter(doc, s.from, s.to) ??
      continueBlockquoteOnEnter(doc, s.from, s.to),
  )
}

// Forward-delete at the end of the line ABOVE a table would join prose into the header row and dissolve
// the whole table to raw pipes. Mirror the backspace atomic behavior instead: a boundary delete removes
// the table as one undoable unit.
const onForwardDelete = (view: EditorView): boolean => {
  const s = view.state.selection.main
  if (!s.empty) return false
  const doc = docString(view.state.doc)
  if (doc[s.from] !== '\n') return false
  const r = tableRegions(doc).find((r) => r.from === s.from + 1)
  if (!r) return false
  view.dispatch({ changes: { from: s.from, to: r.to }, userEvent: 'delete' })
  return true
}

const onBackspace = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = docString(view.state.doc)
  return apply(view, smartBackspace(doc, s.from, s.to) ?? autoDelete(doc, s.from, s.to))
}

// Always returns true so Tab never escapes the editor to focus the sidebar.
const onTab = (view: EditorView): boolean => {
  const s = view.state.selection.main
  apply(view, indentListOnTab(docString(view.state.doc), s.from, s.to))
  return true
}

// Same containment for Shift-Tab: outdent when there's a level to remove, and never blur the editor.
const onShiftTab = (view: EditorView): boolean => {
  const s = view.state.selection.main
  apply(view, outdentListOnShiftTab(docString(view.state.doc), s.from, s.to))
  return true
}

// Shift+Enter exits a construct (plain newline) — except inside a callout, where it stays in the box. If the
// caret sits inside an unclosed pair, it closes that first so the break never lands inside the pair.
const onShiftEnter = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = docString(view.state.doc)
  return apply(
    view,
    closeConstructOnShiftEnter(doc, s.from, s.to) ?? shiftEnterEdit(doc, s.from, s.to),
  )
}

export const markdownInput = [
  Prec.high(
    keymap.of([
      { key: 'Enter', run: onEnter },
      { key: 'Shift-Enter', run: onShiftEnter },
      { key: 'Tab', run: onTab },
      { key: 'Shift-Tab', run: onShiftTab },
      { key: 'Backspace', run: onBackspace },
      { key: 'Delete', run: onForwardDelete },
      // Shift+Backspace ("Shift+Delete" on Mac) joins like Backspace inside a callout instead of falling to the
      // default delete, which would erode the body prefix; the guard backstops every other delete combo.
      { key: 'Shift-Backspace', run: onBackspace },
    ]),
  ),
  EditorView.inputHandler.of((view, from, to, text) => {
    // Never dispatch mid-composition: IME / dead-key input delivers single chars while composing, and a
    // transaction there aborts or garbles the session (CM's own closeBrackets bails the same way).
    if (view.composing || view.compositionStarted) return false
    if (text.length !== 1 || from !== to) return false // single-char inserts only; paste passes through
    const doc = docString(view.state.doc)
    return apply(
      view,
      calloutShorthand(doc, from, from, text) ??
        canonicalizeCheckbox(doc, from, from, text) ??
        autoPair(doc, from, from, text) ??
        dashArrow(doc, from, from, text),
    )
  }),
]
