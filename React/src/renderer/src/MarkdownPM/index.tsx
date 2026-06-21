import { useEffect, useRef, useState } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { markdownDecorations } from './editor/decorations'
import { markdownInput } from './editor/input'
import { connectionClicks } from './editor/connections'
import { autocompleteQuery, connectionInsert } from './autocomplete'
import { AutocompletePanel } from './AutocompletePanel'
import type { ConnectionsApi, ConnPage } from './connections'
import { TitleBar } from './TitleBar'
import { ZOOM_DEFAULT, zoomFontSize } from './zoom'
import './Styles.css'

// Must match the `.cm-content` top padding in Styles.css.
const TITLE_ZONE = 90
const AC_MAX = 6

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
  title?: string
  onRename?: (newName: string) => void | Promise<boolean>
  zoom?: number
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

  // CM6 extensions are built once at mount, so they read live state + actions through refs.
  const [ac, setAc] = useState<AcState | null>(null)
  const [acIndex, setAcIndex] = useState(0)
  const candidates =
    ac && connectionsRef.current
      ? connectionsRef.current
          .candidates(ac.query, AC_MAX + 1)
          .filter((p) => p.title !== title)
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
  const setAcRef = useRef(setAc)
  setAcRef.current = setAc

  useEffect(() => setAcIndex(0), [ac?.query])

  useEffect(() => {
    const parent = host.current
    if (!parent) return
    const view = new EditorView({
      doc: initialBody,
      parent,
      extensions: [
        history(),
        Prec.highest(
          keymap.of([
            { key: 'ArrowDown', run: () => (acCtl.current.open ? (acCtl.current.move(1), true) : false) },
            { key: 'ArrowUp', run: () => (acCtl.current.open ? (acCtl.current.move(-1), true) : false) },
            { key: 'Enter', run: () => (acCtl.current.open ? (acCtl.current.pick(), true) : false) },
            { key: 'Escape', run: () => (acCtl.current.open ? (acCtl.current.close(), true) : false) }
          ])
        ),
        markdownInput,
        keymap.of([...defaultKeymap, ...historyKeymap]),
        markdown(),
        EditorView.lineWrapping,
        markdownDecorations(() => connectionsRef.current),
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
    // Mount once per page — the host keys on path; initialBody is the seed, not a live binding.
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
