import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { duration, text } from '@renderer/design-system/tokens'
import { SortableZone, useDragItem, type DragItem } from '@renderer/design-system/interactions/drag'
import { suppressNextClick } from '@renderer/design-system/interactions/shared'
import type { Tab } from '@shared/types'
import { useSession } from '../store'
import { buildResolveIndex, resolveWith, type ResolvedNav } from '../Navigation/navResolve'
import { EntityGlyph } from '../Navigation/EntityGlyph'
import { cycle, derivePinnedTabs } from './tabsModel'
import './tabStrip.css'
import './tabBar.css'

const BASE_MS = Number.parseInt(duration.base, 10)
/** The tab close/open width window: the standard token plus one fast beat for the segment's delayed
 *  exit (the ghost stays rendered until the whole sequence lands). */
const EXIT_MS = BASE_MS + Number.parseInt(duration.fast, 10)

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
        res: tab.target.kind === 'newtab' || !index ? null : resolveWith(index, tab.target),
      })),
    [index, tabs],
  )

  // Blank ONLY for the pure empty state (a lone NavView, no pins); otherwise the bar shows so the +
  // stays reachable — even at a single real tab (Nathan's revision of D-6's blank-at-single).
  if (pinnedEntries.length === 0 && unpinnedEntries.every((e) => e.tab.target.kind === 'newtab'))
    return null
  return <TabBarBody pinnedEntries={pinnedEntries} unpinnedEntries={unpinnedEntries} />
}

function TabBarBody({
  pinnedEntries,
  unpinnedEntries,
}: {
  pinnedEntries: TabEntry[]
  unpinnedEntries: TabEntry[]
}): React.JSX.Element {
  const activeTabId = useSession((s) => s.activeTabId)
  const revealOnHover = useSession((s) => s.personalization.revealTabBarOnHover ?? false)
  const activateTab = useSession((s) => s.activateTab)
  const openNewTab = useSession((s) => s.openNewTab)
  const closeTab = useSession((s) => s.closeTab)
  const pinTab = useSession((s) => s.pinTab)
  const unpinTab = useSession((s) => s.unpinTab)
  const reorderTabs = useSession((s) => s.reorderTabs)
  const reorderPin = useSession((s) => s.reorderPin)

  // Closing is store-first: the tab leaves the store IMMEDIATELY (content switches, dedup/cycle/MRU
  // all read truth — a re-click of the entity spawns fresh instead of resurrecting a zombie), while a
  // GHOST of it stays rendered for the width-collapse exit on the slow token (J-6).
  const [ghosts, setGhosts] = useState<ReadonlyMap<string, { entry: TabEntry; index: number }>>(
    new Map(),
  )
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
  // The live (non-ghost) entries — the zone's reorderable set AND the render base (computed once).
  const liveEntries = useMemo(
    () => unpinnedEntries.filter((e) => !ghosts.has(e.tab.id)),
    [unpinnedEntries, ghosts],
  )
  // The render list: live entries with each ghost spliced back at its remembered slot mid-exit.
  const renderEntries = useMemo<{ entry: TabEntry; ghost: boolean }[]>(() => {
    const live = liveEntries.map((entry) => ({ entry, ghost: false }))
    for (const [, g] of [...ghosts.entries()].sort((a, b) => a[1].index - b[1].index)) {
      live.splice(Math.min(g.index, live.length), 0, { entry: g.entry, ghost: true })
    }
    return live
  }, [liveEntries, ghosts])
  // Index of the first non-ghost tab — drives the leftmost-close segment handoff (F2).
  const firstLive = renderEntries.findIndex((e) => !e.ghost)

  // Ctrl+Tab / Ctrl+Shift+Tab cycles the full visual order, wrapping (I-11 — the one signed-off
  // binding). Lives in the body, so the combo is intercepted exactly while the bar shows.
  const orderedIds = useMemo(
    () => [...pinnedEntries.map((e) => e.tab.id), ...unpinnedEntries.map((e) => e.tab.id)],
    [pinnedEntries, unpinnedEntries],
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

  // A tab's native (Electron) right-click menu (I-12): context out, action back, dispatched against the
  // tab id. Close animates through the ghost path.
  const runTabMenu =
    (tabId: string, pinned: boolean, isNewTab: boolean) =>
    async (e: React.MouseEvent): Promise<void> => {
      e.preventDefault()
      e.stopPropagation()
      const action = await window.nexus.tabMenu({ pinned, isNewTab })
      if (action === 'pin') pinTab(tabId)
      else if (action === 'unpin') unpinTab(tabId)
      else if (action === 'close') requestClose(tabId)
    }

  // JS window mover: a press on the bar's BARE space (not a tab / the + / any button) drags the app
  // window. A native app-region can't do this — it never delivers hover, killing the + reveal on the
  // same pixels — so the bar moves the window itself off screen-coordinate deltas (immune to the
  // window moving under the pointer). Double-click on bare space zooms (the macOS titlebar gesture).
  const onBarDown = (e: React.PointerEvent<HTMLElement>): void => {
    if (e.button !== 0 || (e.target as HTMLElement).closest('.tab, .tab-pinned, button')) return
    const el = e.currentTarget
    const pid = e.pointerId
    el.setPointerCapture(pid)
    let last = { x: e.screenX, y: e.screenY }
    let travel = 0
    const move = (ev: PointerEvent): void => {
      travel += Math.abs(ev.screenX - last.x) + Math.abs(ev.screenY - last.y)
      window.nexus.winDragBy(ev.screenX - last.x, ev.screenY - last.y)
      last = { x: ev.screenX, y: ev.screenY }
    }
    const end = (): void => {
      if (el.hasPointerCapture(pid)) el.releasePointerCapture(pid)
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerup', end)
      el.removeEventListener('pointercancel', end)
      // A real drag releasing over a tab must not read as a click on it.
      if (travel > 3) suppressNextClick()
    }
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', end)
    el.addEventListener('pointercancel', end)
  }
  const onBarDoubleClick = (e: React.MouseEvent): void => {
    if ((e.target as HTMLElement).closest('.tab, .tab-pinned, button')) return
    window.nexus.winZoom()
  }

  return (
    <div
      className={cx('tab-bar', revealOnHover && 'reveal-on-hover')}
      onPointerDown={onBarDown}
      onDoubleClick={onBarDoubleClick}
    >
      {pinnedEntries.length > 0 && (
        <SortableZone
          items={pinnedEntries.map((e) => e.res?.key ?? '')}
          layout="list"
          axis="x"
          onReorder={reorderPin}
        >
          <div className="tab-pinned-zone">
            {pinnedEntries.map((e, i) => (
              <Fragment key={e.tab.id}>
                {i > 0 && <span className="tab-seg" aria-hidden />}
                <PinnedTab
                  entry={e}
                  active={e.tab.id === activeTabId}
                  onActivate={() => activateTab(e.tab.id)}
                  onMenu={runTabMenu(e.tab.id, true, false)}
                />
              </Fragment>
            ))}
          </div>
        </SortableZone>
      )}
      {pinnedEntries.length > 0 && unpinnedEntries.length > 0 && <span className="tab-divider" />}
      <div className="tab-scroll edge-fade-x" ref={stripRef}>
        <SortableZone
          items={liveEntries.map((e) => e.tab.id)}
          layout="list"
          axis="x"
          onReorder={reorderTabs}
        >
          <div className="tab-strip">
            {renderEntries.map(({ entry, ghost }, i) => (
              <Fragment key={entry.tab.id}>
                {/* The segment before this tab closes with it — OR, when the leftmost tab is the ghost (it
                    has no left segment), the segment before the first LIVE tab closes in its place. */}
                {i > 0 && (
                  <span
                    className={cx('tab-seg', (ghost || i === firstLive) && 'is-closing')}
                    aria-hidden
                  />
                )}
                {/* The ghost stays the SAME component type as the live tab — a type swap would remount
                    the DOM node, and a fresh node mounts already-collapsed (no exit slide). is-closing
                    is pointer-inert, so the live handlers are unreachable on it. */}
                <DraggableUnpinnedTab
                  entry={entry}
                  active={!ghost && entry.tab.id === activeTabId}
                  closing={ghost}
                  onActivate={() => activateTab(entry.tab.id)}
                  onClose={() => requestClose(entry.tab.id)}
                  onMenu={runTabMenu(entry.tab.id, false, entry.tab.target.kind === 'newtab')}
                />
              </Fragment>
            ))}
          </div>
        </SortableZone>
      </div>
      {/* Outside the masked scroller — inside it, the edge fade would dim the parked + itself. */}
      <button
        type="button"
        className="tab-plus"
        aria-label="New Tab"
        title="New Tab"
        onClick={openNewTab}
      >
        <Icon name="plus" size={13} />
      </button>
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
  onMenu,
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

/** The zone-registered tab. A ghost keeps this same wrapper (its id has left the zone's items, so the
 *  drag hook is inert on it) — the closing flag is the only difference. */
function DraggableUnpinnedTab(props: {
  entry: TabEntry
  active: boolean
  closing: boolean
  onActivate: () => void
  onClose: () => void
  onMenu: (e: React.MouseEvent) => void
}): React.JSX.Element {
  const drag = useDragItem(props.entry.tab.id)
  return <UnpinnedTab {...props} drag={drag} />
}

/** An unpinned tab: icon + ellipsizing label, the hover-fade × (D-10), width-animated open/close. */
function UnpinnedTab({
  entry,
  active,
  closing,
  drag,
  onActivate,
  onClose,
  onMenu,
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
  // A navigation that swaps this tab's CONTENT (Back/Forward, a genuine select replacing in place)
  // slides the icon + label in from its direction, replayed per step via the seq-keyed remount. A tab
  // SWITCH changes nothing here, so 'tab' stamps stay motionless on the label.
  const slide = useSession((s) =>
    s.navSlide && s.navSlide.source !== 'tab' && s.navSlide.tabId === entry.tab.id
      ? s.navSlide
      : null,
  )
  const slideClass = slide ? (slide.dir === 'back' ? 'nav-slide-back' : 'nav-slide-fwd') : undefined
  return (
    <div
      ref={drag?.setNodeRef}
      style={drag?.style}
      {...drag?.handle}
      data-tab-id={entry.tab.id}
      className={cx(
        'tab',
        text.control.standard,
        active && 'is-active',
        closing && 'is-closing',
        drag?.isDragging && 'is-dragging',
      )}
      title={title}
      onClick={() => {
        if (!drag?.isDragging) onActivate()
      }}
      onContextMenu={onMenu}
    >
      <Fragment key={slide?.seq ?? 0}>
        {isNewTab || !entry.res ? (
          <Icon
            name={isNewTab ? 'copy' : 'file'}
            size={14}
            className={cx('tab-icon', slideClass)}
          />
        ) : (
          <EntityGlyph item={entry.res} size={14} className={cx('tab-icon', slideClass)} />
        )}
        <OverflowScroll className={cx('tab-label', slideClass)}>{title}</OverflowScroll>
      </Fragment>
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
