import { useEffect, useLayoutEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import { EditorView, keymap } from '@codemirror/view'
import { Annotation, EditorState, Prec } from '@codemirror/state'
import { defaultKeymap } from '@codemirror/commands'
import { customCaret } from '../editor/caret'
import { markdownDecorations } from '../editor/decorations'
import { autoPair, autoDelete, type Edit } from '../input'
import { AC_MAX } from '../autocomplete'
import { useConnectionAutocomplete, detectConnectionQuery } from '../useConnectionAutocomplete'
import { AutocompletePanel } from '../AutocompletePanel'
import type { ConnectionsApi } from '../connections'
import type { NavDir } from './navigate'

const noConn = (): undefined => undefined

// Tags a programmatic content sync (the model re-rendered this cell with new text, e.g. after a reorder)
// so the updateListener doesn't treat it as a user edit and echo it back through onCommit.
const silentEdit = Annotation.define<boolean>()

// One dispatch for any input/index Edit — auto-pair and paired-delete share it (the page editor's `apply`
// equivalent, kept cell-local since the cell doesn't scrollIntoView and varies the userEvent).
function applyEdit(view: EditorView, e: Edit | null, userEvent: string): boolean {
  if (!e) return false
  view.dispatch({ changes: { from: e.from, to: e.to, insert: e.insert }, selection: { anchor: e.selection }, userEvent })
  return true
}

export function CellEditor({
  initial,
  onCommit,
  onNavigate,
  onUndo,
  onRedo,
  caretCoords,
  connections
}: {
  initial: string
  onCommit: (text: string) => void
  onNavigate: (dir: NavDir) => void
  onUndo: () => void
  onRedo: () => void
  // The cell only mounts when it's the active cell, so it focuses itself: at the click point if one was
  // captured (StaticCell mousedown), otherwise at the end (keyboard navigation into the cell).
  caretCoords?: { x: number; y: number } | null
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit
  const onNavigateRef = useRef(onNavigate)
  onNavigateRef.current = onNavigate
  const onUndoRef = useRef(onUndo)
  onUndoRef.current = onUndo
  const onRedoRef = useRef(onRedo)
  onRedoRef.current = onRedo

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
          customCaret,
          EditorView.lineWrapping,
          // Native spell-check, opted in explicitly: the cell editor sits inside the table widget's
          // contentEditable=false host, which suppresses the spell-check the page editor inherits by default.
          EditorView.contentAttributes.of({ spellcheck: 'true' }),
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
              { key: 'Shift-Enter', run: (view) => (view.dispatch(view.state.replaceSelection('\n')), true) },
              // Backspace inside an empty auto-pair deletes both halves (the cell otherwise falls to the default
              // single-char delete, which would leave the stray closer); same autoDelete the page editor uses.
              {
                key: 'Backspace',
                run: (view) => {
                  const s = view.state.selection.main
                  return applyEdit(view, autoDelete(view.state.doc.toString(), s.from, s.to), 'delete')
                }
              },
              // Undo/redo scope to the whole page (the main editor's history) like everywhere else — not a
              // per-cell stack. The main editor can't catch these itself (the widget's ignoreEvent), so the
              // cell forwards them.
              { key: 'Mod-z', run: () => (onUndoRef.current(), true) },
              { key: 'Mod-Shift-z', run: () => (onRedoRef.current(), true) },
              { key: 'Mod-y', run: () => (onRedoRef.current(), true) }
            ])
          ),
          keymap.of(defaultKeymap),
          // Character-pair auto-pairing only (not the main editor's list/blockquote input) so the `[[…]]`
          // query closes and autocomplete can fire.
          EditorView.inputHandler.of((view, from, to, text) => {
            if (text.length !== 1 || from !== to) return false
            return applyEdit(view, autoPair(view.state.doc.toString(), from, from, text), 'input')
          }),
          // Close the connection panel when focus leaves the cell (Tab to the next cell, click away).
          EditorView.domEventHandlers({
            blur: () => {
              setAc(null)
              return false
            }
          }),
          EditorView.updateListener.of((u) => {
            if (u.docChanged && !u.transactions.some((t) => t.annotation(silentEdit)))
              onCommitRef.current(u.state.doc.toString())
            if (u.docChanged || u.selectionSet) detectConnectionQuery(u.view, setAc)
          })
        ]
      })
    })
    viewRef.current = view
    // Focus + land the caret: at the click point (posAtCoords) if one was captured, else at the end.
    // posAtCoords reads layout and can throw before the view has measured — fall back to the end.
    view.focus()
    let pos: number | null = null
    try {
      if (caretCoords) pos = view.posAtCoords({ x: caretCoords.x, y: caretCoords.y })
    } catch {
      pos = null
    }
    view.dispatch({ selection: { anchor: pos ?? view.state.doc.length } })
    return () => {
      view.destroy()
      viewRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount once; the cell IS the live editor
  }, [])

  // The model can re-render this positional cell with different text (a reorder moves content between
  // cells; a page undo reverts it). Sync the live editor to it. Safe even while focused: the model only
  // changes on a rebuild, never mid-keystroke (cell edits remap without rebuilding), so nothing in
  // progress is stomped — and a focused undo MUST update the cell the caret sits in.
  useLayoutEffect(() => {
    const view = viewRef.current
    if (!view || view.state.doc.toString() === initial) return
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: initial },
      annotations: silentEdit.of(true)
    })
  }, [initial])

  return (
    <>
      <div ref={host} className="mdpm-tbl-cell-editor" />
      {createPortal(
        <AutocompletePanel
          open={ac !== null}
          candidates={candidates}
          index={acIndex}
          left={ac?.left ?? 0}
          top={acTop}
          query={ac?.query ?? ''}
          onPick={commit}
        />,
        document.body
      )}
    </>
  )
}
