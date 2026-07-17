import { useEffect, useRef, useState } from 'react'
import { MarkdownEditor } from '@renderer/MarkdownPM'
import type { ConnectionsApi } from '@renderer/MarkdownPM/connections'
import './embeds.css'

const SAVE_DEBOUNCE_MS = 400
/** The embed's fixed zoom-out (G-10), as a LINEAR scale — converted once to the
 *  editor's exponential zoom. The knob. */
import { EMBED_SCALE, EMBED_ZOOM } from './embedScale'

// THE shared page-embed framework (G-11): a window onto a real Page inside a
// foreign surface — SurfacePM's page-embed tiles now, MarkdownPM's ![[Embed]]
// later. It IS the CM6 view (a read-only portal at rest, full decorations);
// entering edit reconfigures the SAME view's editability — no remount, no
// jitter. An embed edit IS a page edit: body writes flow through the page's own
// debounced save (H-2). Header chrome (banner + title) is parked — it returns
// with the ⋮ toggle pass; entry fields stay wired.

export function PageEmbed({
  path,
  editing,
  onBeginEdit,
  connections,
  locked = false,
  registerFlush,
}: {
  /** Nexus-relative path to the `.md` — the page's address for load + save. */
  path: string
  editing: boolean
  onBeginEdit: () => void
  connections?: ConnectionsApi
  /** B-5 content lock: a locked embed can't be entered for editing (stays a selectable portal). */
  locked?: boolean
  /** Opt-in awaitable-flush registration (the pageFlush pattern) for hosts whose close defers unmount. */
  registerFlush?: (fn: (() => Promise<void>) | null) => void
}): React.JSX.Element {
  const [body, setBody] = useState<string | null>(null)
  const pending = useRef<{ timer: ReturnType<typeof setTimeout>; body: string } | null>(null)

  useEffect(() => {
    let live = true
    setBody(null)
    void window.nexus.openPage(path).then((r) => {
      if (live) setBody(r.ok ? r.page.body : '')
    })
    return () => {
      live = false
    }
  }, [path])

  const flush = (): Promise<void> => {
    const p = pending.current
    if (!p) return Promise.resolve()
    clearTimeout(p.timer)
    pending.current = null
    return window.nexus.updatePageBody(path, p.body).then(() => undefined)
  }
  const flushRef = useRef(flush)
  flushRef.current = flush
  useEffect(() => () => void flushRef.current(), [])
  useEffect(() => {
    if (!editing) void flushRef.current()
  }, [editing])
  // Hosts whose close path outlives the world (the preview's exit-presence) register an awaitable
  // flush so pending writes land BEFORE the world changes — the unmount flush alone fires too late.
  useEffect(() => {
    if (!registerFlush) return
    registerFlush(() => flushRef.current())
    return () => registerFlush(null)
  }, [registerFlush])
  const scheduleSave = (next: string): void => {
    if (pending.current) clearTimeout(pending.current.timer)
    pending.current = { body: next, timer: setTimeout(() => flushRef.current(), SAVE_DEBOUNCE_MS) }
  }

  if (body === null) return <div className="pgembed" />
  return (
    // biome-ignore lint/a11y/useKeyWithClickEvents: edit entry is pointer-first
    <div
      className={`pgembed${editing ? ' is-editing' : ''}`}
      style={{ '--mdpm-scale': EMBED_SCALE } as React.CSSProperties}
      onClick={() => {
        if (editing || locked) return // locked: no edit entry; selection still works
        const sel = window.getSelection()
        if (sel && !sel.isCollapsed) return
        onBeginEdit()
      }}
    >
      <MarkdownEditor
        initialBody={body}
        onChange={scheduleSave}
        connections={connections}
        readOnly={!editing}
        autoFocus
        zoom={EMBED_ZOOM}
        edgeFade
      />
    </div>
  )
}
