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
  smartBackspace,
  canonicalizeCheckbox,
  autoPair,
  autoDelete,
  bracketSkipOnEnter,
  dashArrow,
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
  // Bracket-skip first (jump past a closer), else continue the list. Plain Enter only — Shift+Enter
  // isn't bound here, so it falls through to a plain newline (the list/blockquote exit).
  return apply(view, bracketSkipOnEnter(doc, s.from, s.to) ?? continueListOnEnter(doc, s.from, s.to))
}

const onBackspace = (view: EditorView): boolean => {
  const s = view.state.selection.main
  const doc = view.state.doc.toString()
  return apply(view, smartBackspace(doc, s.from, s.to) ?? autoDelete(doc, s.from, s.to))
}

export const markdownInput = [
  Prec.high(
    keymap.of([
      { key: 'Enter', run: onEnter },
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
