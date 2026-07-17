// The renderer's block-document session for one host: load once on host open
// (E-3 — never the tree walk), decode the layout through SurfacePM's repairing
// codec, and persist layout changes with a trailing debounce that flushes on
// unmount so a navigation inside the window can't drop a gesture.

import { useCallback, useEffect, useRef, useState } from 'react'
import type { BlockHostRef } from '@shared/blocks'
import { decodeLayout, encodeLayout } from '@renderer/SurfacePM/core/codec'
import { emptyLayout, type SurfaceLayout } from '@renderer/SurfacePM/core/model'

const SAVE_DEBOUNCE_MS = 300

interface BlockDocState {
  layout: SurfaceLayout
  blocks: unknown[]
  ready: boolean
}

export interface BlockDocSession extends BlockDocState {
  setLayout: (layout: SurfaceLayout) => void
  commitLayout: (update: SurfaceLayout | ((cur: SurfaceLayout) => SurfaceLayout)) => void
  refreshEntries: () => void
  saveBlocks: (update: unknown[] | ((cur: unknown[]) => unknown[])) => void
}

export function useBlockDoc(host: BlockHostRef): BlockDocSession {
  const [state, setState] = useState<BlockDocState>({
    layout: emptyLayout(),
    blocks: [],
    ready: false,
  })
  const hostRef = useRef(host)
  hostRef.current = host
  const pending = useRef<{
    timer: ReturnType<typeof setTimeout> | null
    layout: SurfaceLayout | null
  }>({
    timer: null,
    layout: null,
  })

  // The always-current layout — async continuations (IPC .then) must never build
  // on a render-captured layout; a gesture committing during the await would be
  // silently overwritten.
  const liveLayout = useRef<SurfaceLayout>(state.layout)

  useEffect(() => {
    let cancelled = false
    void window.nexus.blocks.get(hostRef.current).then((r) => {
      if (cancelled || !r.ok) return
      const layout = decodeLayout(r.doc.layout) ?? emptyLayout()
      liveLayout.current = layout
      setState({ layout, blocks: r.doc.blocks, ready: true })
    })
    return () => {
      cancelled = true
    }
  }, [host.kind])

  const flush = useCallback(() => {
    const p = pending.current
    if (p.timer) clearTimeout(p.timer)
    if (p.layout) void window.nexus.blocks.save(hostRef.current, { layout: encodeLayout(p.layout) })
    pending.current = { timer: null, layout: null }
  }, [])

  useEffect(() => flush, [flush])

  const setLayout = useCallback(
    (layout: SurfaceLayout) => {
      liveLayout.current = layout
      setState((s) => ({ ...s, layout }))
      const p = pending.current
      if (p.timer) clearTimeout(p.timer)
      p.layout = layout
      p.timer = setTimeout(flush, SAVE_DEBOUNCE_MS)
    },
    [flush],
  )

  // Immediate variant — structural mutations (tile create/remove) write the layout
  // NOW, before their entry op runs, so a crash leaves an invisible orphan rather
  // than a dead box. Takes an updater so async callers compose with the LIVE
  // layout, never a stale render capture.
  const commitLayout = useCallback(
    (update: SurfaceLayout | ((cur: SurfaceLayout) => SurfaceLayout)) => {
      const layout = typeof update === 'function' ? update(liveLayout.current) : update
      liveLayout.current = layout
      setState((s) => ({ ...s, layout }))
      pending.current.layout = layout
      flush()
    },
    [flush],
  )

  /** Re-pull the entry list after a main-side blocks[] mutation; the local layout stays. */
  const refreshEntries = useCallback(() => {
    void window.nexus.blocks.get(hostRef.current).then((r) => {
      if (r.ok) setState((s) => ({ ...s, blocks: r.doc.blocks }))
    })
  }, [])

  // Entry writes take an updater for the same reason commitLayout does — a menu
  // or IPC window between capture and write must not clobber concurrent changes.
  const liveBlocks = useRef<unknown[]>(state.blocks)
  liveBlocks.current = state.blocks

  /** Write the entry list (per-entry field edits, e.g. style) — immediate. */
  const saveBlocks = useCallback((update: unknown[] | ((cur: unknown[]) => unknown[])) => {
    const next = typeof update === 'function' ? update(liveBlocks.current) : update
    liveBlocks.current = next
    setState((s) => ({ ...s, blocks: next }))
    void window.nexus.blocks.save(hostRef.current, { blocks: next })
  }, [])

  return { ...state, setLayout, commitLayout, refreshEntries, saveBlocks }
}
