// The CM6 input adapter — wires the framework-free input transforms (Phase 1) into CodeMirror.
// Enter / Backspace go through a high-precedence keymap; single-character inserts go through an
// inputHandler (so auto-pair / dash-arrow / checkbox-canon fire before the literal char lands).
// Each transform returns an Edit or null; a non-null Edit is applied as one transaction (so it's a
// single, undoable user action) and consumes the keystroke. Multi-char inserts (paste, IME) fall
// through untouched — paste preserves literal text by construction.
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
  // Bracket-skip first (jump past a closer), else continue a list, else continue a blockquote.
  // Plain Enter only — Shift+Enter is bound separately to a plain newline (the construct exit).
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

const onTab = (view: EditorView): boolean => {
  const s = view.state.selection.main
  return apply(view, indentListOnTab(view.state.doc.toString(), s.from, s.to))
}

// Shift+Enter is the construct EXIT (spec §6.7): a plain newline, never a list/blockquote continue.
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
    if (text.length !== 1 || from !== to) return false // single-char inserts only (paste/IME pass through)
    const doc = view.state.doc.toString()
    return apply(
      view,
      canonicalizeCheckbox(doc, from, from, text) ?? autoPair(doc, from, from, text) ?? dashArrow(doc, from, from, text)
    )
  })
]
