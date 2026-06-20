// The public front door — a React component that hosts a CodeMirror 6 editor over a page's
// Markdown body. Uncontrolled by design: the body is the INITIAL doc, edits flow out via
// onChange; the host remounts per page (key on the path) so there's no body-sync-on-keystroke.
import { useEffect, useRef } from 'react'
import { EditorView, keymap, drawSelection } from '@codemirror/view'
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { markdownDecorations } from './editor/decorations'
import './Styles.css'

interface Props {
  initialBody: string
  onChange: (body: string) => void
}

export function MarkdownEditor({ initialBody, onChange }: Props): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange

  useEffect(() => {
    const parent = host.current
    if (!parent) return
    const view = new EditorView({
      doc: initialBody,
      parent,
      extensions: [
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        markdown(),
        EditorView.lineWrapping,
        drawSelection(),
        markdownDecorations,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) onChangeRef.current(u.state.doc.toString())
        })
      ]
    })
    return () => view.destroy()
    // Mount once per page (the host keys on path); initialBody is the seed, not a live binding.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return <div ref={host} className="mdpm-editor" />
}
