import { useEffect, useMemo, useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { duration, text } from '@renderer/design-system/tokens'
import { SortableZone, useDragItem, type DragItem } from '@renderer/design-system/interactions/drag'
import type { Tab } from '@shared/types'
import { useSession } from '../store'
import { buildResolveIndex, resolveWith, type ResolvedNav } from '../Navigation/navResolve'
import { EntityGlyph } from '../Navigation/EntityGlyph'
import { cycle, derivePinnedTabs } from './tabsModel'
import { TabContextMenu } from './TabContextMenu'
import './tabBar.css'

/** The tab close/open width animation window — the shared slow token (J-6). */
const EXIT_MS = Number.parseInt(duration.slow, 10)

interface TabEntry {
  tab: Tab
  /** Live-resolved display, or null for the NavView tab (rendered off its own treatment). A pinned
   *  tab that no longer resolves render-hides upstream (I-2) and never reaches here. */
  res: ResolvedNav | null
}

/** The toolbar tab bar: pinned compact icons docked left (the pins set, C-1), the unpinned strip
 *  right of them (overflow-scroll + edge fade), the trailing `+`. Blank until there's a working set
 *  to show — two tabs, or a pin (D-6). The gate/body split keeps every interaction hook (the Ctrl+Tab
 *  listener included) mounted exactly when the bar shows. */
export function TabBar(): React.JSX.Element | null {
  const tabs = useSession((s) => s.tabs)
  const pins = useSession((s) => s.pins)
  const tree = useSession((s) => s.tree)

  // Titles + icons resolve live off the nav layer's index — a rename is current on the next push,
  // never cached stale. Built once per tree (memoized), shared by every tab.
  const index = useMemo(() => (tree ? buildResolveIndex(tree) : null), [tree])
  const pinnedEntries = useMemo<TabEntry[]>(() => {
    if (!index) return []
    // A pinned entity that no longer resolves render-hides (I-2: render-prune, never storage-prune).
    return derivePinnedTabs(pins).flatMap((tab) => {
      if (tab.target.kind === 'newtab') return []
      const res = resolveWith(index, tab.target)
      return res ? [{ tab, res }] : []
    })
  }, [index, pins])
  const unpinnedEntries = useMemo<TabEntry[]>(
    () =>
      tabs.map((tab) => ({
        tab,
        res: tab.target.kind === 'newtab' || !index ? null : resolveWith(index, tab.target)
      })),
    [index, tabs]
  )

  if (unpinnedEntries.length < 2 && pinnedEntries.length === 0) return null
  return <TabBarBody pinnedEntries={pinnedEntries} unpinnedEntries={unpinnedEntries} />
}

function TabBarBody({ pinnedEntries, unpinnedEntries }: { pinnedEntries: TabEntry[]; unpinnedEntries: TabEntry[] }): React.JSX.Element {
  const activeTabId = useSession((s) => s.activeTabId)
  const revealOnHover = useSession((s) => s.personalization.revealTabBarOnHover ?? false)
  const activateTab = useSession((s) => s.activateTab)
  const openNewTab = useSession((s) => s.openNewTab)
  const closeTab = useSession((s) => s.closeTab)
  const reorderTabs = useSession((s) => s.reorderTabs)
  const reorderPin = useSession((s) => s.reorderPin)
  const tabs = useSession((s) => s.tabs)

  // Closing is store-first: the tab leaves the store IMMEDIATELY (content switches, dedup/cycle/MRU
  // all read truth — a re-click of the entity spawns fresh instead of resurrecting a zombie), while a
  // GHOST of it stays rendered for the width-collapse exit on the slow token (J-6).
  const [ghosts, setGhosts] = useState<ReadonlyMap<string, { entry: TabEntry; index: number }>>(new Map())
  const requestClose = (id: string): void => {
    const index = unpinnedEntries.findIndex((e) => e.tab.id === id)
    const entry = unpinnedEntries[index]
    if (!entry) return
    setGhosts((m) => new Map(m).set(id, { entry, index }))
    closeTab(id)
    setTimeout(() => {
      setGhosts((m) => {
        const next = new Map(m)
        next.delete(id)
        return next
      })
    }, EXIT_MS)
  }
  // The render list: live entries with each ghost spliced back at its remembered slot mid-exit.
  const renderEntries = useMemo<{ entry: TabEntry; ghost: boolean }[]>(() => {
    const live = unpinnedEntries.filter((e) => !ghosts.has(e.tab.id)).map((entry) => ({ entry, ghost: false }))
    for (const [, g] of [...ghosts.entries()].sort((a, b) => a[1].index - b[1].index)) {
      live.splice(Math.min(g.index, live.length), 0, { entry: g.entry, ghost: true })
    }
    return live
  }, [unpinnedEntries, ghosts])

  // Ctrl+Tab / Ctrl+Shift+Tab cycles the full visual order, wrapping (I-11 — the one signed-off
  // binding). Lives in the body, so the combo is intercepted exactly while the bar shows.
  const orderedIds = useMemo(
    () => [...pinnedEntries.map((e) => e.tab.id), ...unpinnedEntries.map((e) => e.tab.id)],
    [pinnedEntries, unpinnedEntries]
  )
  const cycleRef = useRef({ orderedIds, activeTabId })
  cycleRef.current = { orderedIds, activeTabId }
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (e.key !== 'Tab' || !e.ctrlKey || e.metaKey || e.altKey) return
      e.preventDefault()
      const { orderedIds: ids, activeTabId: active } = cycleRef.current
      activateTab(cycle(ids, active, e.shiftKey ? -1 : 1))
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [activateTab])

  // The active tab scrolls into view on switch (J-5).
  const stripRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    stripRef.current
      ?.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(activeTabId)}"]`)
      ?.scrollIntoView({ inline: 'nearest', block: 'nearest' })
  }, [activeTabId])

  const [menu, setMenu] = useState<{ tabId: string; pinned: boolean; isNewTab: boolean; x: number; y: number } | null>(null)
  const openMenu = (tabId: string, pinned: boolean, isNewTab: boolean) => (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setMenu({ tabId, pinned, isNewTab, x: e.clientX, y: e.clientY })
  }

  const hasRight = (id: string): boolean => {
    const i = tabs.findIndex((t) => t.id === id)
    return i !== -1 && i < tabs.length - 1
  }

  return (
    <div className={cx('tab-bar', revealOnHover && 'reveal-on-hover')}>
      {pinnedEntries.length > 0 && (
        <SortableZone items={pinnedEntries.map((e) => e.res?.key ?? '')} layout="list" axis="x" onReorder={reorderPin}>
          <div className="tab-pinned-zone">
            {pinnedEntries.map((e) => (
              <PinnedTab
                key={e.tab.id}
                entry={e}
                active={e.tab.id === activeTabId}
                onActivate={() => activateTab(e.tab.id)}
                onMenu={openMenu(e.tab.id, true, false)}
              />
            ))}
          </div>
        </SortableZone>
      )}
      {pinnedEntries.length > 0 && unpinnedEntries.length > 0 && <span className="tab-divider" />}
      <div className="tab-scroll" ref={stripRef}>
        <SortableZone items={unpinnedEntries.filter((e) => !ghosts.has(e.tab.id)).map((e) => e.tab.id)} layout="list" axis="x" onReorder={reorderTabs}>
          <div className="tab-strip">
            {renderEntries.map(({ entry, ghost }) =>
              ghost ? (
                <UnpinnedTab key={entry.tab.id} entry={entry} active={false} closing onActivate={() => {}} onClose={() => {}} onMenu={() => {}} />
              ) : (
                <DraggableUnpinnedTab
                  key={entry.tab.id}
                  entry={entry}
                  active={entry.tab.id === activeTabId}
                  onActivate={() => activateTab(entry.tab.id)}
                  onClose={() => requestClose(entry.tab.id)}
                  onMenu={openMenu(entry.tab.id, false, entry.tab.target.kind === 'newtab')}
                />
              )
            )}
          </div>
        </SortableZone>
      </div>
      {/* Outside the masked scroller — inside it, the edge fade would dim the parked + itself. */}
      <button type="button" className="tab-plus" aria-label="New Tab" title="New Tab" onClick={openNewTab}>
        <Icon name="plus" size={13} />
      </button>
      {menu && (
        <TabContextMenu
          tabId={menu.tabId}
          pinned={menu.pinned}
          isNewTab={menu.isNewTab}
          hasRight={!menu.pinned && hasRight(menu.tabId)}
          x={menu.x}
          y={menu.y}
          onClose={() => setMenu(null)}
        />
      )}
    </div>
  )
}

/** A pinned tab: the compact entity icon (the nexus photo for Homepage, via EntityGlyph); the full
 *  name reveals on hover (I-8). The pin badge is pulled for now — position (left of the divider) +
 *  compactness carry the pinned reading. Not closable (D-10) — unpin first. */
function PinnedTab({
  entry,
  active,
  onActivate,
  onMenu
}: {
  entry: TabEntry
  active: boolean
  onActivate: () => void
  onMenu: (e: React.MouseEvent) => void
}): React.JSX.Element | null {
  const drag = useDragItem(entry.res?.key ?? '')
  if (!entry.res) return null
  return (
    <div
      ref={drag.setNodeRef}
      style={drag.style}
      {...drag.handle}
      data-tab-id={entry.tab.id}
      className={cx('tab-pinned', active && 'is-active', drag.isDragging && 'is-dragging')}
      title={entry.res.title}
      onClick={() => {
        if (!drag.isDragging) onActivate()
      }}
      onContextMenu={onMenu}
    >
      <EntityGlyph item={entry.res} size={14} className="tab-icon" />
    </div>
  )
}

/** The zone-registered live tab (a ghost renders UnpinnedTab bare — same shape, no drag). */
function DraggableUnpinnedTab(props: {
  entry: TabEntry
  active: boolean
  onActivate: () => void
  onClose: () => void
  onMenu: (e: React.MouseEvent) => void
}): React.JSX.Element {
  const drag = useDragItem(props.entry.tab.id)
  return <UnpinnedTab {...props} closing={false} drag={drag} />
}

/** An unpinned tab: icon + ellipsizing label, the hover-fade × (D-10), width-animated open/close. */
function UnpinnedTab({
  entry,
  active,
  closing,
  drag,
  onActivate,
  onClose,
  onMenu
}: {
  entry: TabEntry
  active: boolean
  closing: boolean
  drag?: DragItem
  onActivate: () => void
  onClose: () => void
  onMenu: (e: React.MouseEvent) => void
}): React.JSX.Element {
  const isNewTab = entry.tab.target.kind === 'newtab'
  const title = isNewTab ? 'New Tab' : (entry.res?.title ?? '')
  return (
    <div
      ref={drag?.setNodeRef}
      style={drag?.style}
      {...drag?.handle}
      data-tab-id={entry.tab.id}
      className={cx('tab', text.control.standard, active && 'is-active', closing && 'is-closing', drag?.isDragging && 'is-dragging')}
      title={title}
      onClick={() => {
        if (!drag?.isDragging) onActivate()
      }}
      onContextMenu={onMenu}
    >
      {isNewTab || !entry.res ? (
        <Icon name={isNewTab ? 'copy' : 'file'} size={14} className="tab-icon" />
      ) : (
        <EntityGlyph item={entry.res} size={14} className="tab-icon" />
      )}
      <span className="tab-label">{title}</span>
      {/* The chip ×'s glyph + swallow behavior (J-1) with a plain hover-fade — never the melt
          (glass has no solid fill), never on pinned tabs. */}
      <button
        type="button"
        className="tab-x"
        aria-label="Close Tab"
        onPointerDown={(e) => e.stopPropagation()}
        onClick={(e) => {
          e.stopPropagation()
          onClose()
        }}
      >
        <Icon name="x" size={11} strokeWidth={3} />
      </button>
    </div>
  )
}
