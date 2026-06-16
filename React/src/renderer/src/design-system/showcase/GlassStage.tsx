import {
  useLayoutEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type RefObject
} from 'react'
import { createPortal } from 'react-dom'
import { GlassSurface } from '@renderer/design-system/materials'
import './glass-stage.css'

// The glass panel's box — the single source for both its rendered size and the
// drag-clamp math (CSS fills this via .gl-panel { width/height: 100% }).
const PANEL_W = 200
const PANEL_H = 110

// Three landscape surfaces, top → bottom, the middle one is the glass's home.
const SURFACES = [
  { key: 'philly', img: '/surfaces/philly.jpg' },
  { key: 'forest', img: '/surfaces/forest.jpg' },
  { key: 'mac', img: '/surfaces/mac.png' }
] as const

/**
 * The Materials demo: three stacked landscape surfaces (philly · forest · mac,
 * all the mac photo's aspect ratio) as a backdrop, plus a Pommora-glass panel
 * you can drag ANYWHERE on the page. The glass starts centered over the middle
 * (forest) surface and resets there on reload — position is ephemeral state,
 * never persisted.
 */
export function GlassStage(): React.JSX.Element {
  const forestRef = useRef<HTMLDivElement>(null)
  return (
    <>
      <div className="gl-stage">
        {SURFACES.map((s) => (
          <div
            key={s.key}
            ref={s.key === 'forest' ? forestRef : undefined}
            className="gl-bg"
            style={{ backgroundImage: `url(${s.img})` }}
          />
        ))}
      </div>
      <FloatingGlass anchorRef={forestRef} />
    </>
  )
}

function FloatingGlass({ anchorRef }: { anchorRef: RefObject<HTMLDivElement | null> }): React.JSX.Element | null {
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null)
  const drag = useRef({ active: false, sx: 0, sy: 0, ox: 0, oy: 0, dragged: false })

  // Default: centered over the forest surface (document coords). Re-measure as the
  // page settles (the swatch / type rows grow after mount), but stop once dragged.
  useLayoutEffect(() => {
    const measure = (): void => {
      const el = anchorRef.current
      if (!el || drag.current.dragged) return
      const r = el.getBoundingClientRect()
      setPos({
        x: r.left + window.scrollX + r.width / 2 - PANEL_W / 2,
        y: r.top + window.scrollY + r.height / 2 - PANEL_H / 2
      })
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(document.body)
    return () => ro.disconnect()
  }, [anchorRef])

  const onDown = (e: ReactPointerEvent<HTMLDivElement>): void => {
    if (!pos) return
    drag.current = { active: true, sx: e.clientX, sy: e.clientY, ox: pos.x, oy: pos.y, dragged: true }
    try {
      e.currentTarget.setPointerCapture(e.pointerId)
    } catch {
      // synthetic pointer without a real id
    }
  }
  const onMove = (e: ReactPointerEvent<HTMLDivElement>): void => {
    if (!drag.current.active) return
    const doc = document.documentElement
    setPos({
      x: Math.max(0, Math.min(drag.current.ox + (e.clientX - drag.current.sx), doc.scrollWidth - PANEL_W)),
      y: Math.max(0, Math.min(drag.current.oy + (e.clientY - drag.current.sy), doc.scrollHeight - PANEL_H))
    })
  }
  const onUp = (): void => {
    drag.current.active = false
  }

  if (!pos) return null
  return createPortal(
    <div
      className="gl-float"
      style={{ left: pos.x, top: pos.y, width: PANEL_W, height: PANEL_H }}
      onPointerDown={onDown}
      onPointerMove={onMove}
      onPointerUp={onUp}
    >
      <GlassSurface className="gl-panel" style={{ borderRadius: 16 }}>
        <span className="gl-panel-label">Pommora Glass</span>
      </GlassSurface>
    </div>,
    document.body
  )
}
