import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import { EditorView, keymap } from '@codemirror/view'
import { EditorState, Prec } from '@codemirror/state'
import { defaultKeymap } from '@codemirror/commands'
import { markdownDecorations } from '../editor/decorations'
import { autoPair } from '../input'
import { AC_MAX } from '../autocomplete'
import { useConnectionAutocomplete, detectConnectionQuery } from '../useConnectionAutocomplete'
import { AutocompletePanel } from '../AutocompletePanel'
import type { ConnectionsApi } from '../connections'
import type { NavDir } from './navigate'

const noConn = (): undefined => undefined

// A table cell as a live nested CodeMirror editor: the SAME hidden-syntax inline rendering as the main
// editor (markdownDecorations), always editable, no read/edit visual switch and no focus outline. Tab /
// Shift-Tab / Enter drive cell navigation (handled by the parent so it can cross cells + exit the table);
// they never insert structure. `[[…]]` connections render + autocomplete via the shared hook + panel.
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

  const { ac, setAc, candidates, acIndex, acTop, commit, acCtl } = useConnectionAutocomplete(
    viewRef,
    (query) => connections?.()?.candidates(query, AC_MAX) ?? []
  )

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
              // Tab accepts an open connection candidate (like Enter); otherwise it moves to the next cell.
              { key: 'Tab', run: () => (acCtl.current.open ? acCtl.current.pick() : onNavigateRef.current('next'), true) },
              { key: 'Shift-Tab', run: () => (onNavigateRef.current('prev'), true) },
              // With the connection panel open these keys drive it; otherwise they navigate cells.
              { key: 'Enter', run: () => (acCtl.current.open ? acCtl.current.pick() : onNavigateRef.current('down'), true) },
              { key: 'ArrowDown', run: () => (acCtl.current.open ? (acCtl.current.move(1), true) : false) },
              { key: 'ArrowUp', run: () => (acCtl.current.open ? (acCtl.current.move(-1), true) : false) },
              { key: 'Escape', run: () => (acCtl.current.open ? (acCtl.current.close(), true) : false) },
              // Shift+Enter is the in-cell line break — a real newline (the cell grows taller; the row does
              // NOT split, because cellToSource serializes the newline as <br> on disk).
              { key: 'Shift-Enter', run: (view) => (view.dispatch(view.state.replaceSelection('\n')), true) }
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
          // Close the connection panel when focus leaves the cell (Tab to the next cell, click away).
          EditorView.domEventHandlers({
            blur: () => {
              setAc(null)
              return false
            }
          }),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onCommitRef.current(u.state.doc.toString())
            if (u.docChanged || u.selectionSet) detectConnectionQuery(u.view, setAc)
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
