import { useEffect, useRef } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { EditorState, Prec } from '@codemirror/state'
import { defaultKeymap } from '@codemirror/commands'
import { markdownDecorations } from '../editor/decorations'
import type { ConnectionsApi } from '../connections'
import type { NavDir } from './navigate'

const noConn = (): undefined => undefined

// A table cell as a live nested CodeMirror editor: the SAME hidden-syntax inline rendering as the main
// editor (markdownDecorations), always editable, no read/edit visual switch and no focus outline. Tab /
// Shift-Tab / Enter drive cell navigation (handled by the parent so it can cross cells + exit the table);
// they never insert structure. Multi-line (<br>) cells come in a later slice.
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
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit
  const onNavigateRef = useRef(onNavigate)
  onNavigateRef.current = onNavigate

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
              { key: 'Enter', run: () => (onNavigateRef.current('down'), true) }
            ])
          ),
          keymap.of(defaultKeymap),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onCommitRef.current(u.state.doc.toString())
          })
        ]
      })
    })
    const unregister = register(view)
    return () => {
      unregister()
      view.destroy()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount once; the cell IS the live editor
  }, [])

  return <div ref={host} className="mdpm-tbl-cell-editor" />
}
