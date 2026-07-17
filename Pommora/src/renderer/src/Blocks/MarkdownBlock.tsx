import { useEffect, useRef, useState } from 'react'
import type { BlockHostRef } from '@shared/blocks'
import { MarkdownEditor } from '@renderer/MarkdownPM'
import type { ConnectionsApi } from '@renderer/MarkdownPM/connections'

const SAVE_DEBOUNCE_MS = 400

// A markdown block tile — the CM6 portal: one view per tile, read-only at rest
// (full decorations), editability reconfigured in place while THIS tile is the
// surface's single live editor (E-4's revised at-rest form) — no remount, no
// jitter. Body writes are pure (no frontmatter — D-11) and debounce like the
// page editor's.

export function MarkdownBlock({
  host,
  tileId,
  editing,
  onBeginEdit,
  connections,
  suppressFlush,
  locked = false,
}: {
  host: BlockHostRef
  tileId: string
  editing: boolean
  onBeginEdit: (tileId: string) => void
  connections?: ConnectionsApi
  /** True while this tile is being removed — a flush then would land AFTER the
   *  trash and resurrect the file as an entry-less orphan. */
  suppressFlush?: (tileId: string) => boolean
  /** B-5 content lock: a locked tile can't be entered for editing (it stays a selectable portal). */
  locked?: boolean
}): React.JSX.Element {
  const [body, setBody] = useState<string | null>(null)
  const pending = useRef<{ timer: ReturnType<typeof setTimeout>; body: string } | null>(null)

  useEffect(() => {
    let live = true
    void window.nexus.blocks.readMarkdown(host, tileId).then((r) => {
      if (live) setBody(r.ok ? r.body : '')
    })
    return () => {
      live = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tileId])

  const flush = (): void => {
    const p = pending.current
    if (!p) return
    clearTimeout(p.timer)
    pending.current = null
    if (suppressFlush?.(tileId)) return
    void window.nexus.blocks.writeMarkdown(host, tileId, p.body)
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

  if (body === null) return <div className="blk-md" />
  return (
    // biome-ignore lint/a11y/useKeyWithClickEvents: edit entry is pointer-first; keyboard entry rides Task 6 chrome
    <div
      className={`blk-md${editing ? ' is-editing' : ''}`}
      onClick={() => {
        if (editing || locked) return // locked: no edit entry; selection (portal is read-only) still works
        // Selecting rendered text to copy ends in a click — that's a copy, not an edit.
        const sel = window.getSelection()
        if (sel && !sel.isCollapsed) return
        onBeginEdit(tileId)
      }}
    >
      <MarkdownEditor
        initialBody={body}
        onChange={scheduleSave}
        connections={connections}
        readOnly={!editing}
        autoFocus
        edgeFade
      />
    </div>
  )
}
