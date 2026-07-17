import { useEffect, useMemo, useRef, useState } from 'react'
import { GlassPane, GlassWindow } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import {
  FloatingResizeCorners,
  useFloatingWindow,
} from '../design-system/interactions/FloatingWindow'
import { useExitPresence } from '../design-system/useExitPresence'
import { PageEmbed } from '../Embeds/PageEmbed'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'
import { showConnectionMenu } from '../Embeds/connectionMenu'
import { NavCrumbs } from '../Navigation/NavList'
import { buildResolveIndex, resolveWith } from '../Navigation/navResolve'
import { useSession, type PreviewTarget } from '../store'
import './previewWindow.css'

// KNOB — D-7: the unified floating-chrome opening size (shared with NavWindow's WIN block).
const WIN = { minW: 360, minH: 280, defW: 850, defH: 600 }

// The bare surfaces a window-move may start from. The breadcrumb title is pointer-inert (I-16), so a
// press on it lands on the toolbar beneath and arms the move.
const DRAG_SURFACES = '.pgpreview, .pgpreview-toolbar, .pgpreview-body'

export function PreviewWindow(): React.JSX.Element | null {
  const target = useSession((s) => s.previewTarget)
  const { mounted, closing } = useExitPresence(target !== null)
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

  // Inspector (G-1 shell): a preview-scoped pane; Escape closes it FIRST, then the window (I-21).
  const [inspectorOpen, setInspectorOpen] = useState(false)
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

  // Wiki-links inside the preview stay inside it — a click overtakes the shown page (H-1's shell
  // interim until tabs land).
  const openPreview = useSession((s) => s.openPreview)
  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return {
      ...idx,
      open: (page) => openPreview({ id: page.id, path: page.path }),
      menu: showConnectionMenu,
    }
  }, [tree, openPreview])

  // The F-2 breadcrumb: the page's container chain + the page itself as the last crumb.
  const crumbs = useMemo(() => {
    if (!tree) return []
    const res = resolveWith(buildResolveIndex(tree), {
      kind: 'page',
      id: target.id,
      path: target.path,
    })
    return res ? [...res.path, { icon: res.icon, title: res.title }] : []
  }, [tree, target])

  // B-5 promotion: open for real through the normal select, closing the preview.
  const promote = (): void => {
    closePreview()
    void select({ kind: 'page', id: target.id, path: target.path })
  }

  return (
    <GlassPane
      className={`pgpreview${closing ? ' closing' : ''}${inspectorOpen ? ' is-inspector-open' : ''}`}
      // The glass tint knobs (previewWindow.css) compose here — inline because GlassPane's frost
      // sets its own background.
      style={{
        ...style,
        background: 'color-mix(in srgb, var(--pgpreview-bg) var(--pgpreview-bg-a), transparent)',
      }}
      role="dialog"
      aria-label="Page Preview"
      onPointerDown={onWindowDown}
    >
      <div className="pgpreview-toolbar">
        <div className="pgpreview-title">
          <NavCrumbs path={crumbs} className="pgpreview-crumbs" iconSize={11} />
        </div>
        <div className="pgpreview-actions">
          <button
            type="button"
            className="pgpreview-action"
            title="Inspector"
            aria-pressed={inspectorOpen}
            onClick={() => setInspectorOpen((v) => !v)}
          >
            <Icon name="panel-right" size={13} />
          </button>
          <button type="button" className="pgpreview-action" title="Settings" disabled>
            <Icon name="sliders-horizontal" size={13} />
          </button>
          <button
            type="button"
            className="pgpreview-action"
            title="Open Full Page"
            onClick={promote}
          >
            <Icon name="scan" size={13} />
          </button>
          <button type="button" className="pgpreview-action" title="Close" onClick={closePreview}>
            <Icon name="x" size={14} />
          </button>
        </div>
      </div>
      <div className="pgpreview-body edge-fade">
        <PageEmbed
          key={target.path}
          path={target.path}
          editing={editing}
          onBeginEdit={() => setEditing(true)}
          connections={connections}
        />
      </div>
      <GlassWindow
        className="pgpreview-inspector"
        style={{ background: 'var(--state-muted)' }}
        aria-hidden={!inspectorOpen}
      >
        <div className="pgpreview-inspector-body" />
      </GlassWindow>
      <FloatingResizeCorners startDrag={startDrag} />
    </GlassPane>
  )
}
