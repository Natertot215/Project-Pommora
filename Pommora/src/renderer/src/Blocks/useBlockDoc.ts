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

  return { ...state, setLayout }
}
