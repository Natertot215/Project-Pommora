import { useEffect, useRef, useState } from 'react'
import { MarkdownEditor } from '@renderer/MarkdownPM'
import type { ConnectionsApi } from '@renderer/MarkdownPM/connections'
import './embeds.css'

const SAVE_DEBOUNCE_MS = 400
/** The embed's fixed zoom-out (G-10), as a LINEAR scale — converted once to the
 *  editor's exponential zoom. The knob. */
const EMBED_SCALE = 0.9
const EMBED_ZOOM = 1 + Math.log2(EMBED_SCALE)

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
  connections
}: {
  /** Nexus-relative path to the `.md` — the page's address for load + save. */
  path: string
  editing: boolean
  onBeginEdit: () => void
  connections?: ConnectionsApi
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

  const flush = (): void => {
    const p = pending.current
    if (!p) return
    clearTimeout(p.timer)
    pending.current = null
    void window.nexus.updatePageBody(path, p.body)
  }
  const flushRef = useRef(flush)
  flushRef.current = flush
  useEffect(() => () => flushRef.current(), [])
  useEffect(() => {
    if (!editing) flushRef.current()
  }, [editing])
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
        if (editing) return
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
      />
    </div>
  )
}
