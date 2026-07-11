import { useCallback, useMemo } from 'react'
import { knownBlock, type BlockEntry, type BlockHostRef } from '@shared/blocks'
import { FEEL_PRESETS } from '@renderer/design-system/interactions/feel'
import { insertBand } from '@renderer/SurfacePM/core/ops'
import type { Rect } from '@renderer/SurfacePM/core/rects'
import { SurfaceView } from '@renderer/SurfacePM/SurfaceView'
import { useBlockDoc } from './useBlockDoc'

// The host-facing block surface (G-2): the SurfacePM engine over a persisted
// block document. Tile content resolves per typed entry; a leaf whose id has no
// entry — or an entry this build doesn't know — renders inert and keeps its
// space (E-1/E-2), never crashes the host.

export function BlockSurface({ host }: { host: BlockHostRef }): React.JSX.Element | null {
  const { layout, blocks, ready, setLayout } = useBlockDoc(host)

  const entries = useMemo(() => {
    const map = new Map<string, BlockEntry>()
    for (const raw of blocks) {
      const entry = knownBlock(raw)
      if (entry) map.set(entry.id, entry)
    }
    return map
  }, [blocks])

  const renderTile = useCallback(
    (id: string, _rect: Rect) => {
      const entry = entries.get(id)
      if (!entry) return null // inert — the chassis renders, the space holds
      return null // typed tile renderers land with the content tasks
    },
    [entries]
  )

  // Interim add affordance — the plumbing proof until createMarkdown (Task 2) and
  // the right-click Insert menu (G-9) replace it. Layout-only leaves are legal.
  const addTile = useCallback(() => {
    setLayout(insertBand(layout, layout.bands.length, crypto.randomUUID(), 160))
  }, [layout, setLayout])

  if (!ready) return null
  return (
    <div className="blk-surface">
      {/* Blocks reflow on Glide — the roomier displacement feel for big surfaces. */}
      <SurfaceView layout={layout} onLayoutChange={setLayout} renderTile={renderTile} feel={FEEL_PRESETS.Glide} />
      <button type="button" onClick={addTile}>
        Add Block
      </button>
    </div>
  )
}
