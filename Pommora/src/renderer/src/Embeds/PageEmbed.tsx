import { useEffect, useRef, useState } from 'react'
import { MarkdownEditor, type WarmSeam } from '@renderer/MarkdownPM'
import type { ConnectionsApi } from '@renderer/MarkdownPM/connections'
import { flushPageSave, schedulePageSave } from '@renderer/Detail/pageFlush'
import './embeds.css'
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
  onBody,
  warm,
}: {
  /** Nexus-relative path to the `.md` — the page's address for load + save. */
  path: string
  editing: boolean
  onBeginEdit: () => void
  connections?: ConnectionsApi
  /** B-5 content lock: a locked embed can't be entered for editing (stays a selectable portal). */
  locked?: boolean
  /** Opt-in live-body reporting: fires the current editor body on load and on every change. The
   *  floating preview uses it to drive its own Subfield stats from a LOCAL buffer — never the shared
   *  `liveBody` slot (single-owner; a second writer would evict the main pane's live count). */
  onBody?: (body: string) => void
  /** Opt-in warmth (H-8): a restored entry mounts the editor synchronously (its doc IS the body —
   *  no fetch, no blank frame); capture fires at editor unmount. Block tiles mount cold. */
  warm?: WarmSeam
}): React.JSX.Element {
  // The body is bound to the path it was loaded FOR — an un-keyed host swapping `path` in place
  // (a tile re-aimed at another page) blanks and refetches, exactly as a fresh mount would. A warm
  // hit seeds it from the restored editor state's serialized doc: no fetch, no blank frame.
  const [loaded, setLoaded] = useState<{ path: string; body: string } | null>(() => {
    const doc = (warm?.restore()?.editorState as { doc?: unknown } | undefined)?.doc
    return typeof doc === 'string' ? { path, body: doc } : null
  })
  const body = loaded?.path === path ? loaded.body : null

  // Seed the consumer with the current body once it's known (warm or fetched); edits report via onChange.
  const onBodyRef = useRef(onBody)
  onBodyRef.current = onBody
  useEffect(() => {
    if (body !== null) onBodyRef.current?.(body)
  }, [body])

  useEffect(() => {
    if (body !== null) return // already holding this path's body (warm mount or a done fetch)
    let live = true
    void window.nexus.openPage(path).then((r) => {
      if (live) setLoaded({ path, body: r.ok ? r.page.body : '' })
    })
    return () => {
      live = false
    }
  }, [path, body])

  // The debounced write lives in the shared path-keyed autosave (pageFlush) — writes are keyed to
  // the path they were scheduled under, so a host re-aiming `path` in place can never land the old
  // page's body on the new one. Exiting edit (or a path swap / unmount) flushes that page now.
  useEffect(() => {
    if (!editing) void flushPageSave(path)
    return () => void flushPageSave(path)
  }, [editing, path])

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
        onChange={(next) => {
          onBodyRef.current?.(next)
          schedulePageSave(path, next)
        }}
        connections={connections}
        readOnly={!editing}
        autoFocus
        zoom={EMBED_ZOOM}
        edgeFade
        warm={warm}
      />
    </div>
  )
}
