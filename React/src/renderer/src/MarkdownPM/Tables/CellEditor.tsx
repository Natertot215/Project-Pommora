import { useEffect, useRef } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { EditorState, Prec } from '@codemirror/state'
import { defaultKeymap } from '@codemirror/commands'
import { markdownDecorations } from '../editor/decorations'
import type { ConnectionsApi } from '../connections'

const noConn = (): undefined => undefined

// A table cell rendered as a live nested CodeMirror editor: the SAME hidden-syntax inline rendering as
// the main editor (markdownDecorations), always editable — there is no read-vs-edit visual switch and no
// focus effect (the CSS clears CM's focus outline). Single-line for now: Enter is consumed so a stray
// newline can't break the GFM row; multi-line (<br>) and Tab/Enter cell navigation come in later slices.
export function CellEditor({
  initial,
  onCommit,
  connections
}: {
  initial: string
  onCommit: (text: string) => void
  connections?: () => ConnectionsApi | undefined
}): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit

  useEffect(() => {
    const view = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: initial,
        extensions: [
          markdownDecorations(connections ?? noConn),
          EditorView.lineWrapping,
          Prec.highest(keymap.of([{ key: 'Enter', run: () => true }])),
          keymap.of(defaultKeymap),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onCommitRef.current(u.state.doc.toString())
          })
        ]
      })
    })
    return () => view.destroy()
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount once; the cell IS the live editor
  }, [])

  return <div ref={host} className="mdpm-tbl-cell-editor" />
}
