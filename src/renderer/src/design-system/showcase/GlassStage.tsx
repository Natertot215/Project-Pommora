import { useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react'
import './glass-stage.css'

export const PANEL_W = 200
export const PANEL_H = 110

/**
 * Three side-by-side surfaces — rainbow · aerial forest · Pommora window
 * background — with a draggable glass element you can slide across all three, to
 * see the material over different content. Used by the Materials section.
 */
export function GlassStage({ children }: { children: ReactNode }) {
  const stageRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState({ x: 28, y: 55 })
  const drag = useRef({ active: false, sx: 0, sy: 0, px: 28, py: 55 })

  const onDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    drag.current = { active: true, sx: e.clientX, sy: e.clientY, px: pos.x, py: pos.y }
    try {
      e.currentTarget.setPointerCapture(e.pointerId)
    } catch {
      // no-op (e.g. a synthetic pointer without a real id)
    }
  }
  const onMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!drag.current.active) return
    const stage = stageRef.current
    const w = stage?.clientWidth ?? 480
    const h = stage?.clientHeight ?? 220
    const nx = drag.current.px + (e.clientX - drag.current.sx)
    const ny = drag.current.py + (e.clientY - drag.current.sy)
    setPos({
      x: Math.max(0, Math.min(nx, w - PANEL_W)),
      y: Math.max(0, Math.min(ny, h - PANEL_H))
    })
  }
  const onUp = () => {
    drag.current.active = false
  }

  return (
    <div className="gl-stage" ref={stageRef}>
      <div className="gl-bg gl-bg-rainbow" />
      <div className="gl-bg gl-bg-forest" />
      <div className="gl-bg gl-bg-window" />
      <div
        className="gl-drag"
        style={{ left: pos.x, top: pos.y }}
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={onUp}
      >
        {children}
      </div>
    </div>
  )
}
