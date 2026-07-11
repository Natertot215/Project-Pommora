import { useEffect, useRef, useState } from 'react'
import type { BlockHostRef } from '@shared/blocks'
import { StaticMarkdown } from '@renderer/Embeds/StaticMarkdown'
import { MarkdownEditor } from '@renderer/MarkdownPM'
import type { ConnectionsApi } from '@renderer/MarkdownPM/connections'

const SAVE_DEBOUNCE_MS = 400

// A markdown block tile: static markdown at rest, a live MarkdownPM mounting only
// while THIS tile is the surface's single live editor (E-4). The body loads once
// per tile and stays local truth from then on — edits update it in place, so
// leaving edit mode never needs a disk round-trip. Body writes are pure (no
// frontmatter — D-11) and debounce like the page editor's.

export function MarkdownBlock({
  host,
  tileId,
  editing,
  onBeginEdit,
  connections,
  suppressFlush
}: {
  host: BlockHostRef
  tileId: string
  editing: boolean
  onBeginEdit: (tileId: string) => void
  connections?: ConnectionsApi
  /** True while this tile is being removed — a flush then would land AFTER the
   *  trash and resurrect the file as an entry-less orphan. */
  suppressFlush?: (tileId: string) => boolean
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
  if (editing) {
    return (
      <div className="blk-md is-editing">
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
    )
  }
  return (
    // biome-ignore lint/a11y/useKeyWithClickEvents: edit entry is pointer-first; keyboard entry rides Task 6 chrome
    <div
      className="blk-md"
      onClick={() => {
        // Selecting static text to copy ends in a click — that's a copy, not an edit.
        const sel = window.getSelection()
        if (sel && !sel.isCollapsed) return
        onBeginEdit(tileId)
      }}
    >
      <StaticMarkdown body={body} />
    </div>
  )
}
