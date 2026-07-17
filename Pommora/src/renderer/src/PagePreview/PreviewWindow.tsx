import { useEffect, useMemo, useRef, useState } from 'react'
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
import { EMBED_SCALE } from '../Embeds/embedScale'
import { Subfield } from '../Detail/Subfield/Subfield'
import type { SubfieldScope } from '../Detail/Subfield/subfieldItems'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'
import { showConnectionMenu } from '../Embeds/connectionMenu'
import { useConnectionHover } from '../Embeds/ConnectionHoverCard'
import { registerPreviewFlush } from '../Detail/pageFlush'
import { getDetailPaneRect } from '../Detail/DetailPane'
import { NavCrumbs } from '../Navigation/NavList'
import { buildResolveIndex, resolveWith } from '../Navigation/navResolve'
import { useSession, type PreviewTarget } from '../store'
import { PreviewInspector } from './PreviewInspector'
import { PreviewTabStrip } from './PreviewTabStrip'
import { usePreviewWarm } from './usePreviewWarm'
import './previewWindow.css'

// KNOB — D-7: the unified floating-chrome opening size (shared with NavWindow's WIN block).
const WIN = { minW: 360, minH: 280, defW: 850, defH: 600 }

// KNOB — inspector pane resize bounds; the width slot is SHARED across both flavors'
// inspectors (one pane, one remembered width).
export const INSPECTOR = { min: 180, def: 260, max: 420 }

// The bare surfaces a window-move may start from. The breadcrumb title is pointer-inert (I-16), so a
// press on it lands on the toolbar beneath and arms the move; the tab wrap's bare space moves too
// (a press on a .tab is not the wrap and never arms).
const DRAG_SURFACES =
  '.pgpreview, .pgpreview-toolbar, .pgpreview-body, .pgpreview-tabwrap, .pgpreview-tabscroll, .pgpreview-tabstrip'

// The tab-switch content slide (H-11): the DetailPane's view-slide values on the preview's own stamp.
const SLIDE_PX = 14

// The live-stats debounce (mirrors PageView) — edits coalesce before the count recomputes.
const STATS_DEBOUNCE_MS = 120

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

  // The preview's Subfield counts a LOCAL body — never the shared `liveBody` slot (single-owner; a
  // second writer would evict the main pane's live count to its saved snapshot). PageEmbed reports
  // the body via onBody (load-seed + edits): the first body for a path seeds immediately, edits
  // debounce like PageView's stats buffer. Collapse is session-only (a transient floating surface).
  const [previewBody, setPreviewBody] = useState('')
  const statsTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const seededPath = useRef<string | null>(null)
  useEffect(() => {
    setPreviewBody('')
    // Kill any pending debounced write from the outgoing page so it can't land as a stale count.
    if (statsTimer.current) clearTimeout(statsTimer.current)
  }, [target.path])
  useEffect(
    () => () => {
      if (statsTimer.current) clearTimeout(statsTimer.current)
    },
    [],
  )
  const onPreviewBody = (b: string): void => {
    if (statsTimer.current) clearTimeout(statsTimer.current)
    if (seededPath.current !== target.path) {
      seededPath.current = target.path
      setPreviewBody(b)
      return
    }
    statsTimer.current = setTimeout(() => setPreviewBody(b), STATS_DEBOUNCE_MS)
  }
  const scope = useMemo<SubfieldScope>(
    () => ({ target: { id: target.id, path: target.path }, body: previewBody }),
    [target.id, target.path, previewBody],
  )
  // Collapse (session-only) + the detail-pane reveal pattern: the chevron hides until the cursor
  // nears the footer's bottom-right region (tracked here, not a blocking element) or hovers it.
  const [subfieldOpen, setSubfieldOpen] = useState(true)
  const [subfieldNear, setSubfieldNear] = useState(false)

  // Inspector (G-1/G-3): the shared SidePane shell, overlay-mounted right; Escape closes it FIRST,
  // then the window (I-21).
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [inspW, setInspW] = useState(INSPECTOR.def)
  const [inspResizing, setInspResizing] = useState(false)
  useEffect(() => {
    // Skip an Escape a focused surface already handled (mirrors NavWindow / App.tsx).
    const onKey = (e: KeyboardEvent): void => {
      // The liveness guard mirrors NavWindow's — a stale exiting window must never eat the press.
      if (e.key !== 'Escape' || e.defaultPrevented) return
      if (useSession.getState().preview?.flavor !== 'page') return
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

  // Warmth (H-8): the shared seam — editor state per tab id + body-scroll capture/restore.
  const warmSeam = usePreviewWarm(bodyRef, target.path)

  // B-5 promotion: open for real through the normal select; the window ENGULFS into the pane (A-4).
  const promote = (): void => {
    closePreview('engulf')
    void select({ kind: 'page', id: target.id, path: target.path })
  }

  // The engulf exit (A-4): a FLIP from the window's live rect onto the detail pane's — translate to
  // its center, scale to its box, fade — on the base/standard tokens. WAAPI owns it (the rects are
  // runtime values); the css .engulfing class only suppresses the default scale-out.
  const exitReason = useSession((s) => s.previewExit)
  useEffect(() => {
    if (!closing || useSession.getState().previewExit !== 'engulf') return
    const el = bodyRef.current?.parentElement
    const to = getDetailPaneRect()
    if (!el || !to) return
    const from = el.getBoundingClientRect()
    const dx = to.left + to.width / 2 - (from.left + from.width / 2)
    const dy = to.top + to.height / 2 - (from.top + from.height / 2)
    el.animate(
      [
        { transform: 'translate(0px, 0px) scale(1)', opacity: 1 },
        {
          transform: `translate(${dx}px, ${dy}px) scale(${to.width / from.width}, ${to.height / from.height})`,
          opacity: 0,
        },
      ],
      { duration: Number.parseInt(duration.base, 10), easing: easing.standard, fill: 'forwards' },
    )
  }, [closing])

  const closingClass = !closing
    ? ''
    : exitReason === 'engulf'
      ? ' engulfing'
      : exitReason === 'morph'
        ? ' morphing'
        : ' closing'

  return (
    <GlassPane
      className={`pgpreview${closingClass}${inspectorOpen ? ' is-inspector-open' : ''}${inspResizing ? ' is-inspector-resizing' : ''}${subfieldOpen ? ' subfield-open' : ''}${subfieldNear ? ' subfield-near' : ''}`}
      // The glass tint knobs (previewWindow.css) compose here — inline because GlassPane's frost
      // sets its own background. --mdpm-scale mirrors the embed's so the footer aligns to its column.
      style={
        {
          ...style,
          background: 'color-mix(in srgb, var(--pgpreview-bg) var(--pgpreview-bg-a), transparent)',
          '--pgpreview-inspector-w': `${inspW}px`,
          '--mdpm-scale': EMBED_SCALE,
        } as React.CSSProperties
      }
      role="dialog"
      aria-label="Page Preview"
      onPointerDown={onWindowDown}
      onMouseMove={(e) => {
        const r = e.currentTarget.getBoundingClientRect()
        setSubfieldNear(e.clientX > r.right - 260 && e.clientY > r.bottom - 120)
      }}
      onMouseLeave={() => setSubfieldNear(false)}
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
            <button type="button" className="pgpreview-action" title="Settings">
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
          <button
            type="button"
            className="pgpreview-action"
            title="Close"
            onClick={() => closePreview()}
          >
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
          onBody={onPreviewBody}
          warm={warmSeam}
        />
      </div>
      {/* The preview's own Subfield footer (P1): scoped to THIS page, counting the local body. The
          reveal collapses via CSS height (mirrors the detail footer); the toggle rides above the bar
          when open, inset from the corner resize handle. */}
      <button
        type="button"
        className="pgpreview-subfield-toggle"
        onClick={() => setSubfieldOpen((v) => !v)}
        aria-label={subfieldOpen ? 'Hide footer' : 'Show footer'}
        title={subfieldOpen ? 'Hide footer' : 'Show footer'}
      >
        <Icon name={subfieldOpen ? 'chevron-down' : 'chevron-up'} size="md" />
      </button>
      <div className="pgpreview-subfield">
        <Subfield scope={scope} />
      </div>
      <SidePane
        windowId="preview-inspector"
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
