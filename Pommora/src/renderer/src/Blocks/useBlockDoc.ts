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
  locked: boolean
  ready: boolean
}

export interface BlockDocSession extends BlockDocState {
  setLayout: (layout: SurfaceLayout) => void
  commitLayout: (layout: SurfaceLayout) => void
  refreshEntries: () => void
}

export function useBlockDoc(host: BlockHostRef): BlockDocSession {
  const [state, setState] = useState<BlockDocState>({
    layout: emptyLayout(),
    blocks: [],
    locked: false,
    ready: false
  })
  const hostRef = useRef(host)
  hostRef.current = host
  const pending = useRef<{ timer: ReturnType<typeof setTimeout> | null; layout: SurfaceLayout | null }>({
    timer: null,
    layout: null
  })

  useEffect(() => {
    let cancelled = false
    void window.nexus.blocks.get(hostRef.current).then((r) => {
      if (cancelled || !r.ok) return
      setState({
        layout: decodeLayout(r.doc.layout) ?? emptyLayout(),
        blocks: r.doc.blocks,
        locked: r.doc.locked,
        ready: true
      })
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
      setState((s) => ({ ...s, layout }))
      const p = pending.current
      if (p.timer) clearTimeout(p.timer)
      p.layout = layout
      p.timer = setTimeout(flush, SAVE_DEBOUNCE_MS)
    },
    [flush]
  )

  // Immediate variant — structural mutations (tile create/remove) write the layout
  // NOW, before their entry op runs, so a crash leaves an invisible orphan rather
  // than a dead box (the plan's removal-order rule).
  const commitLayout = useCallback(
    (layout: SurfaceLayout) => {
      setState((s) => ({ ...s, layout }))
      pending.current.layout = layout
      flush()
    },
    [flush]
  )

  /** Re-pull the entry list after a main-side blocks[] mutation; the local layout stays. */
  const refreshEntries = useCallback(() => {
    void window.nexus.blocks.get(hostRef.current).then((r) => {
      if (r.ok) setState((s) => ({ ...s, blocks: r.doc.blocks }))
    })
  }, [])

  return { ...state, setLayout, commitLayout, refreshEntries }
}
