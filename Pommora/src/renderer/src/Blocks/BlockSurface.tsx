import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { knownBlock, type BlockEntry, type BlockHostRef, type BlockStyle, type PagePickerItem, type ViewPick, type ViewPickerItem } from '@shared/blocks'
import { FEEL_PRESETS } from '@renderer/design-system/interactions/feel'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '@renderer/MarkdownPM/connections'
import { attachBelow, insertBand, removeTile as removeLeaf } from '@renderer/SurfacePM/core/ops'
import { SurfaceView, type BackdropTarget } from '@renderer/SurfacePM/SurfaceView'
import { defaultEntityIcon, iconNameOr } from '@renderer/design-system/symbols'
import type { EntityIconKind } from '@shared/types'
import { useSession } from '@renderer/store'
import { findCollection, findCollectionForSet, findSet } from '@renderer/Detail/Scope'
import { mintDefaultView } from '@shared/views'
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import type { SavedView } from '@shared/views'
import { MarkdownBlock } from './MarkdownBlock'
import { BlockHandleMenu } from './BlockHandleMenu'
import { ViewEmbedBlock } from './ViewEmbedBlock'
import { PageEmbedBlock } from './PageEmbedBlock'
import { useBlockDoc } from './useBlockDoc'
import './blocks.css'

const NEW_TILE_H = 160

/** The page-picker drill tree: Collections → their pages, Sets nesting inside — every
 *  row wearing its entity icon (custom, else the kind default). */
function pagePickerItems(tree: NexusTree, defaultIcons?: Partial<Record<EntityIconKind, string>>): PagePickerItem[] {
  const pageItem = (p: { id: string; title: string; icon?: string }): PagePickerItem => ({
    label: p.title,
    icon: iconNameOr(p.icon, defaultEntityIcon('page', defaultIcons)),
    pick: p.id
  })
  const setItem = (s: SetNode): PagePickerItem => ({
    label: s.title,
    icon: iconNameOr(s.icon, defaultEntityIcon('set', defaultIcons)),
    submenu: [...(s.sets ?? []).map(setItem), ...s.pages.map(pageItem)]
  })
  const collectionItem = (c: CollectionNode): PagePickerItem => ({
    label: c.title,
    icon: iconNameOr(c.icon, defaultEntityIcon('collection', defaultIcons)),
    submenu: [...c.sets.map(setItem), ...c.pages.map(pageItem)]
  })
  return [...tree.collections, ...tree.userSections.flatMap((u) => u.collections)].map(collectionItem)
}

/** The view-source drill (G-9): Collections → Sets chevron above that container's
 *  views, a + Custom footer per drill (D-5a: the source is picked here, always).
 *  Sub-Sets carry no views, so only depth-1 Sets drill. */
function viewPickerItems(tree: NexusTree, defaultIcons?: Partial<Record<EntityIconKind, string>>): ViewPickerItem[] {
  const containerViews = (node: CollectionNode | SetNode): ViewPickerItem[] => [
    ...(node.views ?? []).map((v) => ({
      label: v.name,
      icon: iconNameOr(v.icon, 'table'),
      pick: { source_id: node.id, view_id: v.id }
    })),
    { label: '+ Custom', pick: { source_id: node.id, custom: true }, footer: true }
  ]
  const collectionItem = (c: CollectionNode): ViewPickerItem => ({
    label: c.title,
    icon: iconNameOr(c.icon, defaultEntityIcon('collection', defaultIcons)),
    // The collection's own views sit ABOVE its Sets (Nathan's call); + Custom stays the pinned footer.
    submenu: [
      ...containerViews(c),
      ...c.sets.map((s) => ({
        label: s.title,
        icon: iconNameOr(s.icon, defaultEntityIcon('set', defaultIcons)),
        submenu: containerViews(s)
      }))
    ]
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
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  const select = useSession((s) => s.select)

  const entries = useMemo(() => {
    const map = new Map<string, BlockEntry>()
    for (const raw of blocks) {
      const entry = knownBlock(raw)
      if (entry) map.set(entry.id, entry)
    }
    return map
  }, [blocks])

  // ONE tree flatten per push, shared by everything that resolves pages — the
  // connections index and every page-embed lookup (never per-embed walks).
  const flatPages = useMemo(() => (tree ? flattenPages(tree) : []), [tree])
  const pagesById = useMemo(() => new Map(flatPages.map((p) => [p.id, p])), [flatPages])

  // Markdown blocks are link SOURCES (D-8) — the tile editor gets the same
  // [[connection]] autocomplete + click-through the page editor has.
  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flatPages)
    return { ...idx, open: (page) => void select({ kind: 'page', id: page.id, path: page.path }) }
  }, [tree, flatPages, select])

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

  // Turn Into → Page (G-7): the handle menu's drill pane resolved the page; main
  // rewrites the entry and trashes a markdown tile's file.
  const applyPagePick = useCallback(
    (id: string, pageId: string) => {
      setEditingId((cur) => (cur === id ? null : cur))
      void window.nexus.blocks.convertToPage(host, id, pageId).then(refreshEntries)
    },
    [refreshEntries, host]
  )

  // Link View: the drill pane resolved a view to COPY (or + Custom → the blank default
  // against that source's schema); main re-mints the config id payload-local and flips
  // the entry (D-12: copied, never synced).
  const applyViewPick = useCallback(
    (id: string, pick: ViewPick) => {
      if (!tree) return
      const container = findCollection(tree, pick.source_id) ?? findSet(tree, pick.source_id)
      if (!container) return
      const config = pick.custom
        ? mintDefaultView(
            (container.kind === 'collection' ? container : findCollectionForSet(tree, container.id))?.properties ?? []
          )
        : (container.views ?? []).find((v) => v.id === pick.view_id)
      if (!config) return
      setEditingId((cur) => (cur === id ? null : cur))
      void window.nexus.blocks.convertToView(host, id, [{ source_id: pick.source_id, config }]).then(refreshEntries)
    },
    [tree, refreshEntries, host]
  )

  // The handle menu is the in-app PickerMenu (G-16), anchored to the clicked handle;
  // Delete still confirms natively in main first. Style edits spread the RAW entry so
  // foreign fields survive (E-1); Duplicate lands directly below via the attach logic.
  const [handleMenu, setHandleMenu] = useState<{ id: string; el: HTMLElement } | null>(null)
  const onHandleMenu = useCallback((id: string, e: React.MouseEvent) => {
    setHandleMenu({ id, el: e.currentTarget as HTMLElement })
  }, [])
  const setStyle = useCallback(
    (id: string, style: BlockStyle) => {
      saveBlocks((cur) => cur.map((b) => (knownBlock(b)?.id === id ? { ...(b as Record<string, unknown>), style } : b)))
    },
    [saveBlocks]
  )
  const duplicateBlock = useCallback(
    (id: string) => {
      void window.nexus.blocks.duplicateTile(host, id).then((r) => {
        if (!r.ok) return
        refreshEntries()
        commitLayout((cur) => {
          const findH = (n: { kind: string; id?: string; h?: number; children?: unknown[] }): number | null => {
            if (n.kind === 'tile') return n.id === id ? (n.h ?? null) : null
            for (const c of n.children ?? []) {
              const h = findH(c as { kind: string })
              if (h !== null) return h
            }
            return null
          }
          const h = cur.bands.map((b) => findH(b.node)).find((v) => v !== null) ?? NEW_TILE_H
          return attachBelow(cur, id, r.id, h)
        })
      })
    },
    [refreshEntries, commitLayout, host]
  )
  const confirmRemove = useCallback(
    (id: string) => {
      void window.nexus.blocks.confirmRemove().then((ok) => {
        if (ok) removeBlock(id)
      })
    },
    [removeBlock]
  )

  const tileClassName = useCallback(
    (id: string) => {
      const classes = [
        entries.get(id)?.style === 'borderless' ? 'is-borderless' : null,
        editingId === id ? 'is-editing-tile' : null,
        handleMenu?.id === id ? 'handle-pinned' : null // the open picker's anchor stays shown
      ].filter(Boolean)
      return classes.length ? classes.join(' ') : undefined
    },
    [entries, editingId, handleMenu]
  )

  // The scope's payload writer: one view element's copied config swaps in place —
  // updater form + raw spreads, so foreign keys on the entry AND its elements survive (E-1).
  const persistViewConfig = useCallback(
    (entryId: string, index: number, config: SavedView) => {
      saveBlocks((cur) =>
        cur.map((raw) => {
          const e = knownBlock(raw)
          if (e?.id !== entryId || e.type !== 'view') return raw
          const r = raw as Record<string, unknown>
          const views = Array.isArray(r.views) ? [...(r.views as unknown[])] : []
          const el = views[index]
          if (typeof el !== 'object' || el === null) return raw
          views[index] = { ...(el as Record<string, unknown>), config }
          return { ...r, views }
        })
      )
    },
    [saveBlocks]
  )

  const renderTile = useCallback(
    (id: string) => {
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
      if (entry?.type === 'page') {
        const page = pagesById.get(entry.page_id)
        if (!page) return <div className="blk-inert" /> // dead reference — inert, space holds (E-2)
        return (
          <PageEmbedBlock page={page} entryId={entry.id} editing={editingId === id} onBeginEdit={setEditingId} connections={connections} />
        )
      }
      if (entry?.type === 'view') return <ViewEmbedBlock entry={entry} persistViewConfig={persistViewConfig} />
      return <div className="blk-inert" /> // no/foreign/unknown entry — space holds, nothing breaks
    },
    [entries, editingId, connections, suppressFlush, pagesById, host, persistViewConfig]
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
      {handleMenu && entries.get(handleMenu.id) && tree && (
        <BlockHandleMenu
          entry={entries.get(handleMenu.id) as BlockEntry}
          anchor={handleMenu.el}
          pageItems={pagePickerItems(tree, defaultIcons)}
          viewItems={viewPickerItems(tree, defaultIcons)}
          onClose={() => setHandleMenu(null)}
          onPickPage={(pageId) => applyPagePick(handleMenu.id, pageId)}
          onPickView={(pick) => applyViewPick(handleMenu.id, pick)}
          onStyle={(style) => setStyle(handleMenu.id, style)}
          onDuplicate={() => duplicateBlock(handleMenu.id)}
          onRemove={() => confirmRemove(handleMenu.id)}
        />
      )}
    </div>
  )
}
