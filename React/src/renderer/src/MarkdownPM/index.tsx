// The public front door — a React component that hosts a CodeMirror 6 editor over a page's
// Markdown body. Uncontrolled by design: the body is the INITIAL doc, edits flow out via
// onChange; the host remounts per page (key on the path) so there's no body-sync-on-keystroke.
// The inline title sits above the body in a reserved top zone and scroll-tracks with the document.
import { useEffect, useRef } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { markdownDecorations } from './editor/decorations'
import { markdownInput } from './editor/input'
import { TitleBar } from './TitleBar'
import { ZOOM_DEFAULT, zoomFontSize } from './zoom'
import './Styles.css'

/** The reserved title zone (px) — must match the `.cm-content` top padding in Styles.css. The
 *  title translates up by the scroll offset, clamped to this, then clips off-screen. (Swift: 90.) */
const TITLE_ZONE = 90

interface Props {
  initialBody: string
  onChange: (body: string) => void
  /** Page title (= filename). Omit to render bodyless (no title bar). */
  title?: string
  /** Commit a rename of the page's `.md` (host wires to the existing rename op). */
  onRename?: (newName: string) => void
  /** Editor zoom (0–2, default 1.0 = 15pt). Wire a per-page value in later. */
  zoom?: number
}

export function MarkdownEditor({ initialBody, onChange, title, onRename, zoom = ZOOM_DEFAULT }: Props): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const titleRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
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
        markdownInput,
        keymap.of([...defaultKeymap, ...historyKeymap]),
        markdown(),
        EditorView.lineWrapping,
        markdownDecorations,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) onChangeRef.current(u.state.doc.toString())
        })
      ]
    })
    viewRef.current = view
    // Scroll-track the title: translate it up 1:1 with the body scroll, clamped to the title zone,
    // so it clips off as the document scrolls past (no React re-render — DOM write only).
    const onScroll = (): void => {
      const t = titleRef.current
      if (t) t.style.transform = `translateY(${-Math.min(Math.max(view.scrollDOM.scrollTop, 0), TITLE_ZONE)}px)`
    }
    view.scrollDOM.addEventListener('scroll', onScroll, { passive: true })
    return () => {
      view.scrollDOM.removeEventListener('scroll', onScroll)
      view.destroy()
      viewRef.current = null
    }
    // Mount once per page (the host keys on path); initialBody is the seed, not a live binding.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="mdpm-shell" style={{ '--editor-font-size': `${zoomFontSize(zoom)}px` } as React.CSSProperties}>
      {title !== undefined && (
        <TitleBar ref={titleRef} title={title} onRename={onRename} onCommit={() => viewRef.current?.focus()} />
      )}
      <div ref={host} className="mdpm-editor" />
    </div>
  )
}
