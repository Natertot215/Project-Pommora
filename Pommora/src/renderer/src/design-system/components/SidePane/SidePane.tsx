import { useLayoutEffect, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { GlassWindow } from '@renderer/design-system/materials'
import { cx } from '@renderer/design-system/cx'
import './sidePane.css'

// THE side-pane shell (G-3): the NavWindow's favorites rail and the PagePreview's inspector are
// the same component — one material (GlassWindow + state-muted veil), one inner geometry, one
// edge-drag resize with per-window persisted width. Hosts own positioning (in-flow vs overlay),
// the width CSS var their layout math reads (mirrored via onWidthChange), and any slide (--io).

export interface SidePaneBounds {
  min: number
  def: number
  max: number
}

// Widths persist per window id across remounts (the exit-presence pattern), session-only.
const widths = new Map<string, number>()

/** The persisted width for a window's pane — hosts seed their CSS-var state from this so the
 *  first painted frame already carries the restored width (the mirror effect runs post-mount). */
export const sidePaneWidth = (windowId: string, def: number): number => widths.get(windowId) ?? def

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

export function SidePane({
  windowId,
  side,
  bounds,
  open = true,
  className,
  resizeClassName,
  resizeLabel = 'Resize pane',
  onWidthChange,
  onResizingChange,
  children,
}: {
  /** Keys the persisted width — one slot per hosting window. */
  windowId: string
  /** Which window edge the pane hugs; the resize strip drags the OPPOSITE edge. */
  side: 'left' | 'right'
  bounds: SidePaneBounds
  /** Overlay hosts toggle; in-flow hosts leave it true. Gates the strip + aria. */
  open?: boolean
  /** The host's positioning class for the pane (e.g. navwindow-rail / pgpreview-inspector). */
  className?: string
  /** The host's positioning class for the resize strip. */
  resizeClassName?: string
  resizeLabel?: string
  /** Mirror the width into the host's CSS var — its layout math (squeeze, swallow, strip
   *  position) reads the var, never this component. Fires on mount and every drag frame. */
  onWidthChange?: (w: number) => void
  /** Transitions pause while dragging so the pane tracks 1:1 (the house resize rule). */
  onResizingChange?: (resizing: boolean) => void
  children?: React.ReactNode
}): React.JSX.Element {
  const [width, setWidth] = useState(() => sidePaneWidth(windowId, bounds.def))
  // Layout effect: the host's CSS var updates before paint, so a restored width never flashes.
  useLayoutEffect(() => {
    onWidthChange?.(width)
  }, [width, onWidthChange])

  const startResize = (e: ReactPointerEvent<HTMLElement>): void => {
    e.preventDefault()
    const el = e.currentTarget
    const pid = e.pointerId
    el.setPointerCapture(pid)
    const s = { x: e.clientX, w: widths.get(windowId) ?? width }
    onResizingChange?.(true)
    const move = (ev: PointerEvent): void => {
      const dx = ev.clientX - s.x
      // A left pane grows dragging right; a right pane grows dragging left.
      const w = clamp(side === 'left' ? s.w + dx : s.w - dx, bounds.min, bounds.max)
      widths.set(windowId, w)
      setWidth(w)
    }
    const end = (): void => {
      if (el.hasPointerCapture(pid)) el.releasePointerCapture(pid)
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerup', end)
      el.removeEventListener('pointercancel', end)
      onResizingChange?.(false)
    }
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', end)
    el.addEventListener('pointercancel', end)
  }

  return (
    <>
      <GlassWindow
        className={cx('sidepane', className)}
        style={{ background: 'var(--state-muted)' }}
        aria-hidden={!open}
      >
        {children}
      </GlassWindow>
      {open && (
        <div
          className={cx('sidepane-resize', resizeClassName)}
          onPointerDown={startResize}
          role="separator"
          aria-orientation="vertical"
          aria-label={resizeLabel}
        />
      )}
    </>
  )
}
