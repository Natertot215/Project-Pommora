import { useCallback, useEffect, useMemo, useState } from 'react'
import { knownBlock, type BlockEntry, type BlockHostRef } from '@shared/blocks'
import { FEEL_PRESETS } from '@renderer/design-system/interactions/feel'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '@renderer/MarkdownPM/connections'
import { insertBand, removeTile as removeLeaf } from '@renderer/SurfacePM/core/ops'
import type { Rect } from '@renderer/SurfacePM/core/rects'
import { SurfaceView } from '@renderer/SurfacePM/SurfaceView'
import { useSession } from '@renderer/store'
import { MarkdownBlock } from './MarkdownBlock'
import { useBlockDoc } from './useBlockDoc'
import './blocks.css'

const NEW_TILE_H = 160

// The host-facing block surface (G-2): the SurfacePM engine over a persisted
// block document. Tile content resolves per typed entry; a leaf whose id has no
// entry — or an entry this build doesn't know — renders inert and keeps its
// space (E-1/E-2), never crashes the host. One live editor at a time (E-4);
// click-out or Esc exits it.

export function BlockSurface({ host }: { host: BlockHostRef }): React.JSX.Element | null {
  const { layout, blocks, ready, setLayout, commitLayout, refreshEntries } = useBlockDoc(host)
  const [editingId, setEditingId] = useState<string | null>(null)
  const tree = useSession((s) => s.tree)
  const select = useSession((s) => s.select)

  const entries = useMemo(() => {
    const map = new Map<string, BlockEntry>()
    for (const raw of blocks) {
      const entry = knownBlock(raw)
      if (entry) map.set(entry.id, entry)
    }
    return map
  }, [blocks])

  // Markdown blocks are link SOURCES (D-8) — the tile editor gets the same
  // [[connection]] autocomplete + click-through the page editor has.
  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return { ...idx, open: (page) => void select({ kind: 'page', id: page.id, path: page.path }) }
  }, [tree, select])

  useEffect(() => {
    if (!editingId) return
    const onDown = (e: PointerEvent): void => {
      if (!(e.target as Element | null)?.closest?.('.blk-md.is-editing')) setEditingId(null)
    }
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') setEditingId(null)
    }
    document.addEventListener('pointerdown', onDown)
    window.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown)
      window.removeEventListener('keydown', onKey)
    }
  }, [editingId])

  const removeBlock = useCallback(
    (id: string) => {
      if (editingId === id) setEditingId(null)
      // Layout first (invisible orphan beats a dead box on a crash), then the entry + file.
      commitLayout(removeLeaf(layout, id))
      void window.nexus.blocks.removeTile(host, id).then(refreshEntries)
    },
    [layout, commitLayout, refreshEntries, editingId, host]
  )

  const renderTile = useCallback(
    (id: string, _rect: Rect) => {
      const entry = entries.get(id)
      const body =
        entry?.type === 'markdown' ? (
          <MarkdownBlock
            host={host}
            tileId={id}
            editing={editingId === id}
            onBeginEdit={setEditingId}
            connections={connections}
          />
        ) : (
          <div className="blk-inert" /> // no/foreign/not-yet-built entry — space holds, nothing breaks
        )
      return (
        <>
          {body}
          {/* Interim remove — the Task 6 handle menu replaces it. */}
          <button type="button" className="blk-remove" aria-label="Remove block" onClick={() => removeBlock(id)}>
            ✕
          </button>
        </>
      )
    },
    [entries, editingId, connections, removeBlock, host]
  )

  const addBlock = useCallback(() => {
    void window.nexus.blocks.createMarkdown(host).then((r) => {
      if (!r.ok) return
      refreshEntries()
      commitLayout(insertBand(layout, layout.bands.length, r.id, NEW_TILE_H))
    })
  }, [layout, commitLayout, refreshEntries, host])

  if (!ready) return null
  return (
    <div className="blk-surface">
      {/* Blocks reflow on Glide — the roomier displacement feel for big surfaces. */}
      <SurfaceView layout={layout} onLayoutChange={setLayout} renderTile={renderTile} feel={FEEL_PRESETS.Glide} />
      {/* Interim add — the right-click Insert menu (G-9, Task 6) replaces it. */}
      <button type="button" className="blk-add" onClick={addBlock}>
        Add Block
      </button>
    </div>
  )
}
