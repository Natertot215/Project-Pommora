import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { knownBlock, type BlockEntry, type BlockHostRef, type BlockStyle, type PagePickerItem } from '@shared/blocks'
import { FEEL_PRESETS } from '@renderer/design-system/interactions/feel'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '@renderer/MarkdownPM/connections'
import { attachBelow, insertBand, removeTile as removeLeaf } from '@renderer/SurfacePM/core/ops'
import type { Rect } from '@renderer/SurfacePM/core/rects'
import { SurfaceView, type BackdropTarget } from '@renderer/SurfacePM/SurfaceView'
import { useSession } from '@renderer/store'
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import { MarkdownBlock } from './MarkdownBlock'
import { PageEmbedBlock } from './PageEmbedBlock'
import { useBlockDoc } from './useBlockDoc'
import './blocks.css'

const NEW_TILE_H = 160

/** The page-picker drill tree: Collections → their pages, Sets nesting inside. */
function pagePickerItems(tree: NexusTree): PagePickerItem[] {
  const setItem = (s: SetNode): PagePickerItem => ({
    label: s.title,
    submenu: [...(s.sets ?? []).map(setItem), ...s.pages.map((p) => ({ label: p.title, pageId: p.id }))]
  })
  const collectionItem = (c: CollectionNode): PagePickerItem => ({
    label: c.title,
    submenu: [...c.sets.map(setItem), ...c.pages.map((p) => ({ label: p.title, pageId: p.id }))]
  })
  return [...tree.collections, ...tree.userSections.flatMap((u) => u.collections)].map(collectionItem)
}

// The host-facing block surface (G-2): the SurfacePM engine over a persisted
// block document. Tile content resolves per typed entry; a leaf whose id has no
// entry — or an entry this build doesn't know — renders inert and keeps its
// space (E-1/E-2), never crashes the host. One live editor at a time (E-4);
// click-out or Esc exits it.

export function BlockSurface({ host }: { host: BlockHostRef }): React.JSX.Element | null {
  const { layout, blocks, ready, setLayout, commitLayout, refreshEntries, saveBlocks } = useBlockDoc(host)
  const [editingId, setEditingId] = useState<string | null>(null)
  // Tiles mid-removal: their editor's flush-on-unmount must NOT run — the write
  // would land after the trash and resurrect the file as an entry-less orphan.
  const removing = useRef(new Set<string>())
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
    // Capture phase: a gesture handler's stopPropagation (SurfacePM's handles/edges)
    // must not swallow the click-out — any pointerdown outside the live editor exits.
    const onDown = (e: PointerEvent): void => {
      if (!(e.target as Element | null)?.closest?.('.blk-md.is-editing')) setEditingId(null)
    }
    const onKey = (e: KeyboardEvent): void => {
      // CM6 consumes Esc first when its autocomplete is open (preventDefault) —
      // that press closes the popup only, the next one exits the editor.
      if (e.key === 'Escape' && !e.defaultPrevented) setEditingId(null)
    }
    document.addEventListener('pointerdown', onDown, true)
    window.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown, true)
      window.removeEventListener('keydown', onKey)
    }
  }, [editingId])

  // THE removal flow — the handle menu's Remove (main-confirmed) is its trigger.
  // Order is load-bearing: suppress the tile's editor flush, layout first
  // (invisible orphan beats a dead box on a crash), then the entry + file.
  const removeBlock = useCallback(
    (id: string) => {
      removing.current.add(id)
      setEditingId((cur) => (cur === id ? null : cur))
      commitLayout((cur) => removeLeaf(cur, id))
      void window.nexus.blocks.removeTile(host, id).then(refreshEntries)
    },
    [commitLayout, refreshEntries, host]
  )
  const suppressFlush = useCallback((id: string) => removing.current.has(id), [])

  // Turn Into → Page: the native drill picker (Collections → Sets → pages, built
  // here — main has no tree) resolves a page id; main rewrites the entry and
  // trashes a markdown tile's file (G-7).
  const convertToPage = useCallback(
    (id: string) => {
      if (!tree) return
      void window.nexus.blocks.pagePicker(pagePickerItems(tree)).then((pageId) => {
        if (!pageId) return
        setEditingId((cur) => (cur === id ? null : cur))
        void window.nexus.blocks.convertToPage(host, id, pageId).then(refreshEntries)
      })
    },
    [tree, refreshEntries, host]
  )

  // The handle's returning-picker menu: main resolves the action (confirming
  // Remove there), the renderer performs the write. Style edits spread the RAW
  // entry so foreign fields survive (E-1); View converts wait on Task 4's picker.
  const onHandleMenu = useCallback(
    (id: string) => {
      const entry = entries.get(id)
      void window.nexus.blocks
        .handleMenu({ style: entry?.style === 'borderless' ? 'borderless' : 'bordered' })
        .then((action) => {
          if (action === 'remove') removeBlock(id)
          else if (action === 'type:page') convertToPage(id)
          else if (action === 'style:bordered' || action === 'style:borderless') {
            const style = action.slice('style:'.length) as BlockStyle
            saveBlocks(
              blocks.map((b) =>
                knownBlock(b)?.id === id ? { ...(b as Record<string, unknown>), style } : b
              )
            )
          }
        })
    },
    [entries, blocks, saveBlocks, removeBlock, convertToPage]
  )

  const tileClassName = useCallback(
    (id: string) => {
      const classes = [
        entries.get(id)?.style === 'borderless' ? 'is-borderless' : null,
        editingId === id ? 'is-editing-tile' : null
      ].filter(Boolean)
      return classes.length ? classes.join(' ') : undefined
    },
    [entries, editingId]
  )

  const renderTile = useCallback(
    (id: string, _rect: Rect) => {
      const entry = entries.get(id)
      if (entry?.type === 'markdown')
        return (
          <MarkdownBlock
            host={host}
            tileId={id}
            editing={editingId === id}
            onBeginEdit={setEditingId}
            connections={connections}
            suppressFlush={suppressFlush}
          />
        )
      if (entry?.type === 'page')
        return (
          <PageEmbedBlock entry={entry} editing={editingId === id} onBeginEdit={setEditingId} connections={connections} />
        )
      return <div className="blk-inert" /> // no/foreign/not-yet-built entry — space holds, nothing breaks
    },
    [entries, editingId, connections, suppressFlush, host]
  )

  // Right-click on the surface background creates a block (G-9's Block default,
  // menu-less until Task 6): a wedge target fits flush inside the ragged gap, an
  // append lands as a new full-width band. Updater form — a gesture committing
  // during the IPC await must not be overwritten by a render-captured layout.
  const onBackdrop = useCallback(
    (target: BackdropTarget) => {
      void window.nexus.blocks.createMarkdown(host).then((r) => {
        if (!r.ok) return
        refreshEntries()
        commitLayout((cur) =>
          target.kind === 'wedge'
            ? attachBelow(cur, target.above, r.id, target.fillPx)
            : insertBand(cur, cur.bands.length, r.id, NEW_TILE_H)
        )
      })
    },
    [commitLayout, refreshEntries, host]
  )

  if (!ready) return null
  return (
    <div className={`blk-surface${editingId ? ' has-live-editor' : ''}`}>
      {/* Blocks reflow on Glide — the roomier displacement feel for big surfaces. */}
      <SurfaceView
        layout={layout}
        onLayoutChange={setLayout}
        renderTile={renderTile}
        feel={FEEL_PRESETS.Glide}
        tileClassName={tileClassName}
        onHandleMenu={onHandleMenu}
        onBackdrop={onBackdrop}
      />
    </div>
  )
}
