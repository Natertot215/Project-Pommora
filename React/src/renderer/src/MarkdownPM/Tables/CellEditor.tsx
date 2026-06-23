import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { EditorView, keymap } from '@codemirror/view'
import { EditorState, Prec } from '@codemirror/state'
import { defaultKeymap } from '@codemirror/commands'
import { markdownDecorations } from '../editor/decorations'
import { autoPair } from '../input'
import { autocompleteQuery, connectionInsert, AC_MAX, acPanelTop } from '../autocomplete'
import { AutocompletePanel } from '../AutocompletePanel'
import type { ConnectionsApi, ConnPage } from '../connections'
import type { NavDir } from './navigate'

const noConn = (): undefined => undefined

interface AcState {
  query: string
  from: number
  to: number
  left: number
  caretTop: number
  caretBottom: number
}

// A table cell as a live nested CodeMirror editor: the SAME hidden-syntax inline rendering as the main
// editor (markdownDecorations), always editable, no read/edit visual switch and no focus outline. Tab /
// Shift-Tab / Enter drive cell navigation (handled by the parent so it can cross cells + exit the table);
// they never insert structure. `[[…]]` connections render + autocomplete via the shared panel. Multi-line
// (<br>) cells come in a later slice.
export function CellEditor({
  initial,
  onCommit,
  onNavigate,
  register,
  connections
}: {
  initial: string
  onCommit: (text: string) => void
  onNavigate: (dir: NavDir) => void
  register: (view: EditorView) => () => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit
  const onNavigateRef = useRef(onNavigate)
  onNavigateRef.current = onNavigate

  const [ac, setAc] = useState<AcState | null>(null)
  const [acIndex, setAcIndex] = useState(0)
  const setAcRef = useRef(setAc)
  setAcRef.current = setAc

  const candidates = ac ? (connections?.()?.candidates(ac.query, AC_MAX) ?? []) : []

  const commit = (page: ConnPage): void => {
    const view = viewRef.current
    if (!view || !ac) return
    const { insert, caret } = connectionInsert(page.title, ac.from)
    view.dispatch({ changes: { from: ac.from, to: ac.to, insert }, selection: { anchor: caret }, userEvent: 'input' })
    setAc(null)
    view.focus()
  }

  // The mounted editor's keymap reads the open panel through this ref (the state itself lives in React).
  const acCtl = useRef({ open: false, pick: () => {}, move: (_d: number) => {}, close: () => {} })
  acCtl.current = {
    open: ac !== null && candidates.length > 0,
    pick: () => {
      const p = candidates[acIndex]
      if (p) commit(p)
    },
    move: (d) => setAcIndex((i) => Math.max(0, Math.min(i + d, candidates.length - 1))),
    close: () => setAc(null)
  }

  useEffect(() => setAcIndex(0), [ac?.query])

  useEffect(() => {
    const view = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: initial,
        extensions: [
          markdownDecorations(connections ?? noConn),
          EditorView.lineWrapping,
          Prec.highest(
            keymap.of([
              { key: 'Tab', run: () => (onNavigateRef.current('next'), true) },
              { key: 'Shift-Tab', run: () => (onNavigateRef.current('prev'), true) },
              // With the connection panel open these keys drive it; otherwise they navigate cells.
              { key: 'Enter', run: () => (acCtl.current.open ? acCtl.current.pick() : onNavigateRef.current('down'), true) },
              { key: 'ArrowDown', run: () => (acCtl.current.open ? (acCtl.current.move(1), true) : false) },
              { key: 'ArrowUp', run: () => (acCtl.current.open ? (acCtl.current.move(-1), true) : false) },
              { key: 'Escape', run: () => (acCtl.current.open ? (acCtl.current.close(), true) : false) },
              // Cells are single-line GFM. Shift+Enter is the in-cell soft break — inserts a single space
              // (a real <br> arrives with multi-line cells); Mod+Enter stays reserved. Neither inserts a
              // newline, which would split the row.
              { key: 'Shift-Enter', run: (view) => (view.dispatch(view.state.replaceSelection(' ')), true) },
              { key: 'Mod-Enter', run: () => true }
            ])
          ),
          keymap.of(defaultKeymap),
          // `[[` → `[[]]` auto-pairing only (not the main editor's list/blockquote input) so the `[[…]]`
          // query closes and autocomplete can fire.
          EditorView.inputHandler.of((view, from, to, text) => {
            if (text.length !== 1 || from !== to) return false
            const e = autoPair(view.state.doc.toString(), from, from, text)
            if (!e) return false
            view.dispatch({ changes: { from: e.from, to: e.to, insert: e.insert }, selection: { anchor: e.selection }, userEvent: 'input' })
            return true
          }),
          EditorView.domEventHandlers({
            // Multi-line paste would split the row; flatten newlines to spaces on the way in.
            paste: (event, view) => {
              const text = event.clipboardData?.getData('text/plain')
              if (text == null || !/\r?\n/.test(text)) return false
              event.preventDefault()
              view.dispatch(view.state.replaceSelection(text.replace(/\r?\n/g, ' ')))
              return true
            },
            // Close the panel when focus leaves the cell (Tab to the next cell, click away).
            blur: () => {
              setAcRef.current(null)
              return false
            }
          }),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onCommitRef.current(u.state.doc.toString())
            if (u.docChanged || u.selectionSet) {
              const sel = u.state.selection.main
              let next: AcState | null = null
              if (sel.empty) {
                const q = autocompleteQuery(u.state.doc.toString(), sel.head)
                const c = q && u.view.coordsAtPos(sel.head)
                if (q && c) next = { ...q, left: Math.round(c.left), caretTop: Math.round(c.top), caretBottom: Math.round(c.bottom) }
              }
              setAcRef.current(next)
            }
          })
        ]
      })
    })
    viewRef.current = view
    const unregister = register(view)
    return () => {
      unregister()
      view.destroy()
      viewRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount once; the cell IS the live editor
  }, [])

  const acTop = ac ? acPanelTop(ac.caretTop, ac.caretBottom, candidates.length) : 0

  return (
    <>
      <div ref={host} className="mdpm-tbl-cell-editor" />
      {ac &&
        candidates.length > 0 &&
        createPortal(
          <AutocompletePanel
            candidates={candidates}
            index={acIndex}
            left={ac.left}
            top={acTop}
            query={ac.query}
            onPick={commit}
          />,
          document.body
        )}
    </>
  )
}
