import { useEffect, useRef, useState } from 'react'
import { assetUrl } from '@renderer/assetUrl'
import { MarkdownEditor } from '@renderer/MarkdownPM'
import type { ConnectionsApi } from '@renderer/MarkdownPM/connections'
import { StaticMarkdown } from './StaticMarkdown'
import './embeds.css'

const SAVE_DEBOUNCE_MS = 400

// THE shared page-embed framework (G-11): a scrollable, editable window onto a
// real Page inside a foreign surface. One seam, two consumers — SurfacePM's
// page-embed tiles now, MarkdownPM's ![[Embed]] later — so it speaks in page
// identity + chrome flags, never in tile vocabulary. An embed edit IS a page
// edit: body writes flow through the same debounced page save the full editor
// uses (H-2). Static at rest; the live editor mounts on click-in (E-4).

export function PageEmbed({
  path,
  title,
  editing,
  onBeginEdit,
  onOpen,
  showBanner = true,
  showTitle = true,
  connections
}: {
  /** Nexus-relative path to the `.md` — the page's address for load + save. */
  path: string
  title: string
  editing: boolean
  onBeginEdit: () => void
  /** Navigate to the real page (B-8 — full-page until the preview surface ships). */
  onOpen?: () => void
  showBanner?: boolean
  showTitle?: boolean
  connections?: ConnectionsApi
}): React.JSX.Element {
  const [body, setBody] = useState<string | null>(null)
  const [cover, setCover] = useState<string | undefined>(undefined)
  const pending = useRef<{ timer: ReturnType<typeof setTimeout>; body: string } | null>(null)

  useEffect(() => {
    let live = true
    setBody(null)
    void window.nexus.openPage(path).then((r) => {
      if (!live) return
      if (r.ok) {
        setBody(r.page.body)
        setCover(typeof r.page.frontmatter.cover === 'string' ? r.page.frontmatter.cover : undefined)
      } else {
        setBody('')
      }
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

  // Header chrome (banner + title) is parked — it returns with the ⋮ toggle pass;
  // the fields + props stay wired so nothing re-plumbs.
  void assetUrl
  void cover
  void title
  void onOpen
  void showBanner
  void showTitle
  return (
    <div className="pgembed">
      {body === null ? null : editing ? (
        <div className="pgembed-body is-editing">
          <MarkdownEditor
            initialBody={body}
            onChange={(next) => {
              setBody(next)
              scheduleSave(next)
            }}
            connections={connections}
            autoFocus
          />
        </div>
      ) : (
        // biome-ignore lint/a11y/useKeyWithClickEvents: edit entry is pointer-first
        <div
          className="pgembed-body"
          onClick={() => {
            const sel = window.getSelection()
            if (sel && !sel.isCollapsed) return
            onBeginEdit()
          }}
        >
          <StaticMarkdown body={body} />
        </div>
      )}
    </div>
  )
}
