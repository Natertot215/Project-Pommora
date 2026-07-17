import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { GlassPane } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import { duration, easing } from '@renderer/design-system/tokens'
import { SidePane } from '@renderer/design-system/components/SidePane/SidePane'
import {
  FloatingResizeCorners,
  useFloatingWindow,
} from '../design-system/interactions/FloatingWindow'
import { useExitPresence } from '../design-system/useExitPresence'
import { PageEmbed } from '../Embeds/PageEmbed'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'
import { showConnectionMenu } from '../Embeds/connectionMenu'
import { useConnectionHover } from '../Embeds/ConnectionHoverCard'
import { registerPreviewFlush } from '../Detail/pageFlush'
import { NavCrumbs } from '../Navigation/NavList'
import { buildResolveIndex, resolveWith } from '../Navigation/navResolve'
import { useSession, type PreviewTarget } from '../store'
import { PreviewInspector } from './PreviewInspector'
import { PreviewTabStrip } from './PreviewTabStrip'
import { capturePreviewWarm, readPreviewWarm, type PreviewWarmEntry } from './previewWarm'
import './previewWindow.css'

// KNOB — D-7: the unified floating-chrome opening size (shared with NavWindow's WIN block).
const WIN = { minW: 360, minH: 280, defW: 850, defH: 600 }

// KNOB — inspector pane resize bounds (width persists per-window inside SidePane).
const INSPECTOR = { min: 180, def: 260, max: 420 }

// The bare surfaces a window-move may start from. The breadcrumb title is pointer-inert (I-16), so a
// press on it lands on the toolbar beneath and arms the move; the tab wrap's bare space moves too
// (a press on a .tab is not the wrap and never arms).
const DRAG_SURFACES =
  '.pgpreview, .pgpreview-toolbar, .pgpreview-body, .pgpreview-tabwrap, .pgpreview-tabscroll, .pgpreview-tabstrip'

// The tab-switch content slide (H-11): the DetailPane's view-slide values on the preview's own stamp.
const SLIDE_PX = 14

export function PreviewWindow(): React.JSX.Element | null {
  // The window's existence keys on the PAGE flavor, not the derived target — the nav flavor renders
  // in NavWindow's chrome, and its map tab nulls the target without closing anything (H-2/I-4).
  // A page-flavor window always has an active page tab, so the target is non-null while open.
  const open = useSession((s) => s.preview?.flavor === 'page')
  const target = useSession((s) => s.previewTarget)
  const { mounted, closing } = useExitPresence(open)
  // Hold the last real target through the exit animation (the store nulls it at close). The body is
  // NOT keyed by target: an overtake swaps contents in place — the window never jumps (I-6).
  const held = useRef(target)
  if (target) held.current = target
  if (!mounted || !held.current) return null
  return <PreviewWindowBody target={held.current} closing={closing} />
}

function PreviewWindowBody({
  target,
  closing,
}: {
  target: PreviewTarget
  closing: boolean
}): React.JSX.Element {
  const closePreview = useSession((s) => s.closePreview)
  const select = useSession((s) => s.select)
  const tree = useSession((s) => s.tree)
  const { style, onWindowDown, startDrag } = useFloatingWindow('page-preview', WIN, DRAG_SURFACES)

  // Fully editable (C-2) via the seam's edit flip; a new target starts back at the read-only portal.
  const [editing, setEditing] = useState(false)
  useEffect(() => setEditing(false), [target.path])

  // Inspector (G-1/G-3): the shared SidePane shell, overlay-mounted right; Escape closes it FIRST,
  // then the window (I-21).
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [inspW, setInspW] = useState(INSPECTOR.def)
  const [inspResizing, setInspResizing] = useState(false)
  useEffect(() => {
    // Skip an Escape a focused surface already handled (mirrors NavWindow / App.tsx).
    const onKey = (e: KeyboardEvent): void => {
      if (e.key !== 'Escape' || e.defaultPrevented) return
      if (inspectorOpen) setInspectorOpen(false)
      else closePreview()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [closePreview, inspectorOpen])

  // Wiki-links inside the preview stay inside it — a click opens (or dedup-focuses) a tab (H-1).
  // ⌘-click is ADDITIVE (I-19): a new app tab opens behind, the preview stays.
  const openPreviewTab = useSession((s) => s.openPreviewTab)
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

  const resolveIndex = useMemo(() => (tree ? buildResolveIndex(tree) : null), [tree])

  // The F-2 breadcrumb: the page's container chain + the page itself as the last crumb.
  const crumbs = useMemo(() => {
    if (!resolveIndex) return []
    const res = resolveWith(resolveIndex, { kind: 'page', id: target.id, path: target.path })
    return res ? [...res.path, { icon: res.icon, title: res.title }] : []
  }, [resolveIndex, target])

  // Tab-switch slide: the incoming page slides in from the strip direction (the DetailPane WAAPI
  // pattern on the preview's own stamp), and the open inspector RIDES the same keyframes — the
  // G-4 one-motion push (transform only: the pane never blinks).
  const previewSlide = useSession((s) => s.previewSlide)
  const bodyRef = useRef<HTMLDivElement>(null)
  const prevPath = useRef(target.path)
  const playedSeq = useRef(0)
  useEffect(() => {
    const swapped = prevPath.current !== target.path
    prevPath.current = target.path
    if (!swapped || !previewSlide || previewSlide.seq === playedSeq.current) return
    playedSeq.current = previewSlide.seq
    const x = previewSlide.dir === 'back' ? -SLIDE_PX : SLIDE_PX
    const timing = { duration: Number.parseInt(duration.fast, 10), easing: easing.standard }
    bodyRef.current?.animate(
      [
        { transform: `translateX(${x}px)`, opacity: 0 },
        { transform: 'translateX(0)', opacity: 1 },
      ],
      timing,
    )
    if (inspectorOpen)
      bodyRef.current?.parentElement
        ?.querySelector('.pgpreview-inspector')
        ?.animate([{ transform: `translateX(${x}px)` }, { transform: 'translateX(0)' }], timing)
  }, [target.path, previewSlide, inspectorOpen])

  // Warmth (H-8): the embed's editor state keys on the ACTIVE preview-tab id. The seam binds at
  // the editor's mount (its mount-once effect freezes the closure), so a switch's unmount capture
  // always lands under the tab that owned it. Captures are LIVENESS-GATED: the editor's unmount
  // capture trails the store's drop (close-the-active-tab, window close), and ungated it would
  // re-insert every dropped id — one ghost editorState per close, accumulating all session.
  const activePreviewTabId = useSession((s) => s.preview?.activeTabId)
  const captureIfLive = useCallback((tabId: string, entry: PreviewWarmEntry): void => {
    const p = useSession.getState().preview
    if (p?.tabs.some((t) => t.id === tabId)) capturePreviewWarm(tabId, entry)
  }, [])
  const warmSeam = useMemo(
    () =>
      activePreviewTabId
        ? {
            restore: () => readPreviewWarm(activePreviewTabId),
            capture: (state: { editorState: unknown; scrollTop: number }) =>
              captureIfLive(activePreviewTabId, state),
          }
        : undefined,
    [activePreviewTabId, captureIfLive],
  )

  // Per-tab BODY scroll warmth: the preview's one scroller is the body (the editor chain never
  // overflows here), so the window tracks it — a passive listener records the active tab's scroll
  // as it happens (no switch-time read of a maybe-clamped value), and a switch restores the
  // incoming tab's after its embed committed (child effects run first, so content height exists).
  useEffect(() => {
    const el = bodyRef.current
    if (!el || !activePreviewTabId) return
    const onScroll = (): void => captureIfLive(activePreviewTabId, { bodyScrollTop: el.scrollTop })
    el.addEventListener('scroll', onScroll, { passive: true })
    return () => el.removeEventListener('scroll', onScroll)
  }, [activePreviewTabId])
  useEffect(() => {
    if (!activePreviewTabId) return
    const saved = readPreviewWarm(activePreviewTabId)?.bodyScrollTop ?? 0
    // CM6 builds the embed's height ASYNC after mount — an immediate set clamps to 0 on the
    // not-yet-tall body (and the listener would record the clamp as truth). Double-rAF lands
    // after its first measure/layout pass; the restore's own scroll event then re-captures right.
    let inner = 0
    const outer = requestAnimationFrame(() => {
      inner = requestAnimationFrame(() => {
        if (bodyRef.current) bodyRef.current.scrollTop = saved
      })
    })
    return () => {
      cancelAnimationFrame(outer)
      cancelAnimationFrame(inner)
    }
    // target.path IS the switch signal — the effect must fire per content swap, not per tab-id.
    // biome-ignore lint/correctness/useExhaustiveDependencies: see above
  }, [target.path])

  // B-5 promotion: open for real through the normal select, closing the preview.
  const promote = (): void => {
    closePreview()
    void select({ kind: 'page', id: target.id, path: target.path })
  }

  return (
    <GlassPane
      className={`pgpreview${closing ? ' closing' : ''}${inspectorOpen ? ' is-inspector-open' : ''}${inspResizing ? ' is-inspector-resizing' : ''}`}
      // The glass tint knobs (previewWindow.css) compose here — inline because GlassPane's frost
      // sets its own background.
      style={
        {
          ...style,
          background: 'color-mix(in srgb, var(--pgpreview-bg) var(--pgpreview-bg-a), transparent)',
          '--pgpreview-inspector-w': `${inspW}px`,
        } as React.CSSProperties
      }
      role="dialog"
      aria-label="Page Preview"
      onPointerDown={onWindowDown}
    >
      <div className="pgpreview-toolbar">
        <div className="pgpreview-actions">
          <button
            type="button"
            className="pgpreview-action"
            title="Open Full Page"
            onClick={promote}
          >
            <Icon name="scan" size={13} />
          </button>
        </div>
        <PreviewTabStrip
          index={resolveIndex}
          title={<NavCrumbs path={crumbs} className="pgpreview-crumbs" iconSize={11} />}
        />
        <div className="pgpreview-actions">
          {/* The flow pair rides the inspector's edge (the main toolbar's --io swallow); the X
              holds home. */}
          <div className="pgpreview-actions-flow">
            <button type="button" className="pgpreview-action" title="Settings" disabled>
              <Icon name="sliders-horizontal" size={13} />
            </button>
            <button
              type="button"
              className="pgpreview-action"
              title="Inspector"
              aria-pressed={inspectorOpen}
              onClick={() => setInspectorOpen((v) => !v)}
            >
              <Icon name="panel-right" size={13} />
            </button>
          </div>
          <button type="button" className="pgpreview-action" title="Close" onClick={closePreview}>
            <Icon name="x" size={14} />
          </button>
        </div>
      </div>
      <div className="pgpreview-body edge-fade" ref={bodyRef}>
        <PageEmbed
          key={target.path}
          path={target.path}
          editing={editing}
          onBeginEdit={() => setEditing(true)}
          connections={connections}
          registerFlush={registerPreviewFlush}
          warm={warmSeam}
        />
      </div>
      <SidePane
        windowId="page-preview"
        side="right"
        bounds={INSPECTOR}
        open={inspectorOpen}
        className="pgpreview-inspector"
        resizeClassName="pgpreview-inspector-resize"
        resizeLabel="Resize inspector"
        onWidthChange={setInspW}
        onResizingChange={setInspResizing}
      >
        <div className="pgpreview-inspector-body">
          {inspectorOpen && <PreviewInspector target={target} />}
        </div>
      </SidePane>
      {hoverCard}
      <FloatingResizeCorners startDrag={startDrag} />
    </GlassPane>
  )
}
