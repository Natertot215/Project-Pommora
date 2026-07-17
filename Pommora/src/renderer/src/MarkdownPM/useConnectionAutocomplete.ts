import { useEffect, useRef, useState, type RefObject } from 'react'
import type { EditorView } from '@codemirror/view'
import type { ConnPage } from './connections'
import { autocompleteQuery, connectionInsert, acPanelTop } from './autocomplete'

export interface AcState {
  query: string
  from: number
  to: number
  left: number
  caretTop: number
  caretBottom: number
}

export interface AcCtl {
  open: boolean
  pick: () => void
  move: (d: number) => void
  close: () => void
}

export interface ConnectionAutocomplete {
  ac: AcState | null
  setAc: (s: AcState | null) => void
  candidates: ConnPage[]
  acIndex: number
  acTop: number
  commit: (page: ConnPage) => void
  acCtl: RefObject<AcCtl>
}

// The `[[…]]` connection autocomplete state machine, shared by the page editor and table cells. The caller
// supplies the live view (for the insert) + a candidate source — each bakes in its own getter/ref and
// self-filter — and owns where the panel renders (inline vs portal) and its keymap. This owns the rest:
// query state, index clamping, the commit, the panel anchor, and the keymap-facing `acCtl` ref. Pair it
// with detectConnectionQuery() in the editor's updateListener.
export function useConnectionAutocomplete(
  viewRef: RefObject<EditorView | null>,
  candidatesFor: (query: string) => ConnPage[],
): ConnectionAutocomplete {
  const [ac, setAc] = useState<AcState | null>(null)
  const [acIndex, setAcIndex] = useState(0)
  const candidates = ac ? candidatesFor(ac.query) : []

  const commit = (page: ConnPage): void => {
    const view = viewRef.current
    if (!view || !ac) return
    const { insert, caret } = connectionInsert(page.title, ac.from)
    view.dispatch({
      changes: { from: ac.from, to: ac.to, insert },
      selection: { anchor: caret },
      userEvent: 'input',
    })
    setAc(null)
    view.focus()
  }

  // The editor's keymap (built once at mount) reads the live panel state through this ref.
  const acCtl = useRef<AcCtl>({ open: false, pick: () => {}, move: () => {}, close: () => {} })
  acCtl.current = {
    open: ac !== null && candidates.length > 0,
    pick: () => {
      const p = candidates[acIndex]
      if (p) commit(p)
    },
    move: (d) => setAcIndex((i) => Math.max(0, Math.min(i + d, candidates.length - 1))),
    close: () => setAc(null),
  }

  useEffect(() => setAcIndex(0), [ac?.query])

  const acTop = ac ? acPanelTop(ac.caretTop, ac.caretBottom, candidates.length) : 0

  return { ac, setAc, candidates, acIndex, acTop, commit, acCtl }
}

// Recompute the active `[[…]]` query from the live caret and push it to setAc — call from the editor's
// updateListener on doc/selection changes. setAc (a useState setter) is stable, so capturing it once at
// mount is safe; this is a free function rather than a closure so both editors share one detection path.
export function detectConnectionQuery(view: EditorView, setAc: (s: AcState | null) => void): void {
  const sel = view.state.selection.main
  let next: AcState | null = null
  if (sel.empty) {
    const q = autocompleteQuery(view.state.doc.toString(), sel.head)
    const c = q && view.coordsAtPos(sel.head)
    if (q && c)
      next = {
        ...q,
        left: Math.round(c.left),
        caretTop: Math.round(c.top),
        caretBottom: Math.round(c.bottom),
      }
  }
  setAc(next)
}
