// The public front door — a React component hosting a CodeMirror 6 editor over a page's Markdown
// body. Uncontrolled by design: the body is the INITIAL doc, edits flow out via onChange, and the
// host remounts per page (key on path) so there's no body-sync-on-keystroke.
import { useEffect, useRef, useState } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { markdownDecorations } from './editor/decorations'
import { markdownInput } from './editor/input'
import { connectionClicks, connectionStatus } from './editor/connections'
import { autocompleteQuery, connectionInsert } from './autocomplete'
import { AutocompletePanel } from './AutocompletePanel'
import type { ConnectionsApi, ConnPage } from './connections'
import { TitleBar } from './TitleBar'
import { ZOOM_DEFAULT, zoomFontSize } from './zoom'
import './Styles.css'

/** The reserved title zone (px) — must match the `.cm-content` top padding in Styles.css. The
 *  title translates up by the scroll offset, clamped to this, then clips off-screen. (Swift: 90.) */
const TITLE_ZONE = 90
/** Max connection candidates shown at once. */
const AC_MAX = 6

/** Active `[[` autocomplete: the query + the token span to replace + the caret anchor. */
interface AcState {
  query: string
  from: number
  to: number
  left: number
  top: number
}

interface Props {
  initialBody: string
  onChange: (body: string) => void
  /** Page title (= filename). Omit to render bodyless (no title bar). */
  title?: string
  /** Commit a rename of the page's `.md` (host wires to the existing rename op). Resolves the op's
   *  success so the title bar can revert its draft on failure. */
  onRename?: (newName: string) => void | Promise<boolean>
  /** Editor zoom (0–2, default 1.0 = 15pt). Wire a per-page value in later. */
  zoom?: number
  /** Connection resolution + navigation. Read live via a ref so tree changes take effect. */
  connections?: ConnectionsApi
}

export function MarkdownEditor({
  initialBody,
  onChange,
  title,
  onRename,
  zoom = ZOOM_DEFAULT,
  connections
}: Props): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const titleRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange
  const connectionsRef = useRef(connections)
  connectionsRef.current = connections

  // `[[` autocomplete. The CM6 extensions are built once at mount, so they read live state through
  // refs rather than the closed-over values.
  const [ac, setAc] = useState<AcState | null>(null)
  const [acIndex, setAcIndex] = useState(0)
  const candidates =
    ac && connectionsRef.current
      ? connectionsRef.current
          .candidates(ac.query, AC_MAX + 4)
          .filter((p) => p.title !== title) // no self-links
          .slice(0, AC_MAX)
      : []

  const commit = (page: ConnPage): void => {
    const view = viewRef.current
    if (!view || !ac) return
    const { insert, caret } = connectionInsert(page.title, ac.from)
    view.dispatch({ changes: { from: ac.from, to: ac.to, insert }, selection: { anchor: caret }, userEvent: 'input' })
    setAc(null)
    view.focus()
  }

  const acRef = useRef<{ open: boolean; candidates: ConnPage[]; index: number }>({ open: false, candidates: [], index: 0 })
  acRef.current = { open: ac !== null && candidates.length > 0, candidates, index: acIndex }
  const setAcRef = useRef(setAc)
  setAcRef.current = setAc
  const setAcIndexRef = useRef(setAcIndex)
  setAcIndexRef.current = setAcIndex
  const commitRef = useRef(commit)
  commitRef.current = commit

  // Selection resets to the top whenever the query changes (a fresh candidate list).
  useEffect(() => setAcIndex(0), [ac?.query])

  useEffect(() => {
    const parent = host.current
    if (!parent) return
    const view = new EditorView({
      doc: initialBody,
      parent,
      extensions: [
        history(),
        // When the autocomplete is open these intercept nav/accept/dismiss; otherwise fall through.
        Prec.highest(
          keymap.of([
            {
              key: 'ArrowDown',
              run: () => {
                if (!acRef.current.open) return false
                setAcIndexRef.current((i) => Math.min(i + 1, acRef.current.candidates.length - 1))
                return true
              }
            },
            {
              key: 'ArrowUp',
              run: () => {
                if (!acRef.current.open) return false
                setAcIndexRef.current((i) => Math.max(i - 1, 0))
                return true
              }
            },
            {
              key: 'Enter',
              run: () => {
                if (!acRef.current.open) return false
                const p = acRef.current.candidates[acRef.current.index]
                if (p) commitRef.current(p)
                return true
              }
            },
            {
              key: 'Escape',
              run: () => {
                if (!acRef.current.open) return false
                setAcRef.current(null)
                return true
              }
            }
          ])
        ),
        markdownInput,
        keymap.of([...defaultKeymap, ...historyKeymap]),
        markdown(),
        EditorView.lineWrapping,
        markdownDecorations,
        connectionStatus(() => connectionsRef.current),
        connectionClicks(() => connectionsRef.current),
        EditorView.updateListener.of((u) => {
          if (u.docChanged) onChangeRef.current(u.state.doc.toString())
          if (u.docChanged || u.selectionSet) {
            const sel = u.state.selection.main
            let next: AcState | null = null
            if (sel.empty) {
              const q = autocompleteQuery(u.state.doc.toString(), sel.head)
              const c = q && u.view.coordsAtPos(sel.head)
              if (q && c) next = { ...q, left: Math.round(c.left), top: Math.round(c.bottom) }
            }
            setAcRef.current(next)
          }
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
      {ac && (
        <AutocompletePanel
          candidates={candidates}
          index={acIndex}
          left={ac.left}
          top={ac.top}
          query={ac.query}
          onPick={commit}
        />
      )}
    </div>
  )
}
