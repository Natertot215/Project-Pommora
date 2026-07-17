import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import { GlassPane } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { SidePane, sidePaneWidth } from '@renderer/design-system/components/SidePane/SidePane'
import {
  FloatingResizeCorners,
  useFloatingWindow,
} from '../design-system/interactions/FloatingWindow'
import type { NavTarget } from '@shared/types'
import { useExitPresence } from '../design-system/useExitPresence'
import { PageEmbed } from '../Embeds/PageEmbed'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'
import { showConnectionMenu } from '../Embeds/connectionMenu'
import { useConnectionHover } from '../Embeds/ConnectionHoverCard'
import { registerPreviewFlush } from '../Detail/pageFlush'
import { buildResolveIndex } from '../Navigation/navResolve'
import { useSession } from '../store'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import { NavList } from '../Navigation/NavList'
import { PreviewTabStrip } from '../PagePreview/PreviewTabStrip'
import { usePreviewWarm } from '../PagePreview/usePreviewWarm'
import { NavGallery } from './NavGallery'
import './navWindow.css'

// KNOB — the pane's default opening size + the rail's resize bounds (width persists in SidePane).
const WIN = { minW: 360, minH: 280, defW: 850, defH: 600 }
const RAIL = { min: 120, def: 200, max: 320 }

// Persists the List/Gallery choice across opens (the pane remounts each open via useExitPresence).
let savedViewMode: 'list' | 'gallery' = 'list'

// The bare backgrounds a window-move may start from (matched against the press target itself, so any
// child content — row internals, card bodies, the search input — never arms a move).
const DRAG_SURFACES =
  '.navwindow, .navwindow-body, .navwindow-rail, .navwindow-rail-list, .navwindow-main, .navwindow-main-scroll, .navwindow-search, .navwindow-page, .navwindow-tabs, .nav-list, .nav-gallery, .nav-gallery-grid'

export function NavWindow(): React.JSX.Element | null {
  const navOpen = useSession((s) => s.navOpen)
  const { mounted, closing } = useExitPresence(navOpen)
  if (!mounted) return null
  return <NavWindowBody closing={closing} />
}

function NavWindowBody({ closing }: { closing: boolean }): React.JSX.Element {
  const { resolvedRecents, resolvedFavorites, resolvedPins, search, go } = useNavData()
  const closeNav = useSession((s) => s.closeNav)
  const tree = useSession((s) => s.tree)

  // Freeze the recents order at open — navigating while the pane stays open still records into the
  // store's recents, but the visible list must NOT reshuffle placement under the cursor. Re-snapshots
  // on reopen (the body remounts). Filtered against the LIVE pin set (pinning while open drops the
  // card) AND live recents membership (a row-menu Remove drops it) — placement stays frozen either way.
  const [frozenRecents, setFrozenRecents] = useState(resolvedRecents)
  const shownRecents = useMemo(() => {
    const pinned = new Set(resolvedPins.map((p) => p.key))
    const live = new Set(resolvedRecents.map((r) => r.key))
    return frozenRecents.filter((r) => live.has(r.key) && !pinned.has(r.key))
  }, [frozenRecents, resolvedPins, resolvedRecents])
  // A drag is the ONE thing that bypasses the freeze — it's the deliberate reorder. The commit writes
  // the SHOWN order wholesale (setRecentsOrder): the store's live order can lag the frozen view (a
  // click mid-open re-fronts its entry), so an (active, over) splice against it would land elsewhere
  // than the drop showed. Opening a page still leaves placement frozen until a reopen re-snapshots.
  const setRecentsOrder = useSession((s) => s.setRecentsOrder)
  const reorderShownRecent = (activeKey: string, overKey: string): void => {
    const from = frozenRecents.findIndex((r) => r.key === activeKey)
    const to = frozenRecents.findIndex((r) => r.key === overKey)
    if (from === -1 || to === -1 || from === to) return
    const next = [...frozenRecents]
    const [moved] = next.splice(from, 1)
    next.splice(to, 0, moved)
    setFrozenRecents(next)
    setRecentsOrder(next.map((r) => r.key))
  }

  const [query, setQuery] = useState('')
  const searchRef = useRef<HTMLInputElement>(null)
  const {
    style: winStyle,
    onWindowDown,
    startDrag,
  } = useFloatingWindow('navwindow', WIN, DRAG_SURFACES)

  useEffect(() => {
    // Skip an Escape a focused surface already handled (mirrors App.tsx's command handler).
    const onKey = (e: KeyboardEvent): void => {
      // Bail unless this is the LIVE surface — during the 380ms flavor-swap exit both windows'
      // handlers coexist, and a stale one must never eat the press (D-4: one press, one layer).
      if (e.key !== 'Escape' || e.defaultPrevented || !useSession.getState().navOpen) return
      closeNav()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [closeNav])

  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  // Selecting from the pane closes it, unless `navCloseOnSelect` is explicitly off (keep it open to browse).
  const closeOnSelect = useSession((s) => s.tree?.personalization.navCloseOnSelect !== false)
  const goClose = (target: NavTarget): void => go(target, closeOnSelect ? closeNav : undefined)
  // The row/card menu's "Open in New Tab" (D-3) — same reconcile + close-on-select pipeline as a click.
  const goNewTab = (target: NavTarget): void =>
    go(target, closeOnSelect ? closeNav : undefined, { newTab: true })
  // Rail Style toggle — List ⇄ Gallery. The choice persists across opens (module-scoped, like geo).
  const [viewMode, setViewMode] = useState<'list' | 'gallery'>(savedViewMode)
  const toggleViewMode = (): void =>
    setViewMode((m) => {
      savedViewMode = m === 'list' ? 'gallery' : 'list'
      return savedViewMode
    })

  // B-2: the routing override — "Open in Preview" from this window's rows opens a tab HERE instead
  // of the floating preview. Persisted in page-previews.json; default on (the override wins).
  const navOverride = useSession((s) => s.previewsFile.navOverride ?? true)
  const setNavOverride = useSession((s) => s.setNavOverride)

  // The nav flavor (H-2): the whole body below is the MAP TAB's content; an active page tab swaps
  // it away and slides the rail closed (G-4/F-5). The strip is persistent window chrome above it.
  const preview = useSession((s) => s.preview)
  const pageTarget = useSession((s) => (s.preview?.flavor === 'nav' ? s.previewTarget : null))
  // H-2: focus the search on open AND on every map-tab return (a command-palette focus — the
  // input remounts when a page tab swaps the body away).
  useEffect(() => {
    if (!pageTarget) searchRef.current?.focus()
  }, [pageTarget])
  const hasTabs = preview?.flavor === 'nav' && preview.tabs.length > 1
  const resolveIndex = useMemo(() => (tree ? buildResolveIndex(tree) : null), [tree])

  // The page tab's embed: fully editable, same flush + warm seams as the floating preview (D-2:
  // one preview exists at a time, so the single flush slot serves whichever flavor is open).
  const [editing, setEditing] = useState(false)
  useEffect(() => setEditing(false), [pageTarget?.path])
  const pageScrollRef = useRef<HTMLDivElement>(null)
  const warmSeam = usePreviewWarm(pageScrollRef, pageTarget?.path)
  const openPreviewTab = useSession((s) => s.openPreviewTab)
  const select = useSession((s) => s.select)
  const { hover, card: hoverCard } = useConnectionHover()
  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return {
      ...idx,
      open: (page) => openPreviewTab({ id: page.id, path: page.path }),
      bypass: (page) =>
        void select({ kind: 'page', id: page.id, path: page.path }, { newTab: true }),
      hover,
      menu: showConnectionMenu,
    }
  }, [tree, openPreviewTab, select, hover])

  // The rail width lives in SidePane's per-window store; the var feeds the css layout. Seeded
  // from the same store so a reopen's first frame already paints the restored width.
  const [railW, setRailW] = useState(() => sidePaneWidth('navwindow', RAIL.def))
  const style = {
    ...winStyle,
    '--navwindow-rail': `${railW}px`,
  } as CSSProperties

  return (
    <GlassPane
      className={cx('navwindow', closing && 'closing', pageTarget !== null && 'is-page-tab')}
      style={style}
      role="dialog"
      aria-label="Navigation"
      onPointerDown={onWindowDown}
    >
      <button type="button" className="navwindow-close" aria-label="Close" onClick={closeNav}>
        <Icon name="x" size={14} />
      </button>
      {/* F-7: the strip row exists only past one tab — its height grows in, nudging the body down
          on the standard ease; the map tab is the perma-pinned return (H-2/I-4). */}
      <div className={cx('navwindow-tabs', hasTabs && 'has-tabs')}>
        <PreviewTabStrip index={resolveIndex} title={null} />
      </div>
      <div className="navwindow-body">
        <SidePane
          windowId="navwindow"
          side="left"
          bounds={RAIL}
          className="navwindow-rail"
          resizeClassName="navwindow-rail-resize"
          resizeLabel="Resize favorites"
          onWidthChange={setRailW}
        >
          <div className="navwindow-rail-list edge-fade">
            <NavList items={resolvedFavorites} onSelect={goClose} onOpenNewTab={goNewTab} />
          </div>
          <button
            type="button"
            className={cx('navwindow-style-toggle', text.footnote.emphasized)}
            onClick={toggleViewMode}
          >
            <Icon name="chevrons-up-down" size={12} />
            <span>{viewMode === 'list' ? 'List' : 'Gallery'}</span>
          </button>
          <button
            type="button"
            className={cx('navwindow-style-toggle', text.footnote.emphasized)}
            aria-pressed={navOverride}
            title="Where Open in Preview lands: tabs in this window, or the floating preview"
            onClick={() => setNavOverride(!navOverride)}
          >
            <Icon name="app-window" size={12} />
            <span>{navOverride ? 'Tabs' : 'Window'}</span>
          </button>
        </SidePane>
        {pageTarget ? (
          <div className="navwindow-page edge-fade" ref={pageScrollRef}>
            <PageEmbed
              key={pageTarget.path}
              path={pageTarget.path}
              editing={editing}
              onBeginEdit={() => setEditing(true)}
              connections={connections}
              registerFlush={registerPreviewFlush}
              warm={warmSeam}
            />
          </div>
        ) : (
          <div className="navwindow-main">
            <div className="navwindow-search">
              <input
                ref={searchRef}
                className={text.body.standard}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search…"
                spellCheck={false}
              />
            </div>
            <div className="navwindow-main-scroll edge-fade">
              {results ? (
                <NavList
                  items={results.items}
                  extras={results.extras}
                  onSelect={goClose}
                  onOpenNewTab={goNewTab}
                />
              ) : viewMode === 'gallery' ? (
                <NavGallery
                  pins={resolvedPins}
                  items={shownRecents}
                  onReorderRecent={reorderShownRecent}
                  onSelect={goClose}
                  onOpenNewTab={goNewTab}
                />
              ) : (
                <NavList
                  pins={resolvedPins}
                  items={shownRecents}
                  reorderable
                  onReorderRecent={reorderShownRecent}
                  onSelect={goClose}
                  onOpenNewTab={goNewTab}
                />
              )}
            </div>
          </div>
        )}
      </div>
      {hoverCard}
      <FloatingResizeCorners startDrag={startDrag} />
    </GlassPane>
  )
}
