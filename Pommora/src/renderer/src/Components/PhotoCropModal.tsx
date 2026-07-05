import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { GlassSurface } from '@renderer/design-system/materials'
import * as s from './photoCropModal.css'

// Geometry (px): the square viewport, the crop circle centered inside it, and the
// exported avatar resolution. The circle's bounding box is what gets exported.
const VIEWPORT = 280
const CIRCLE = 220
const RADIUS = CIRCLE / 2
const INSET = (VIEWPORT - CIRCLE) / 2
const OUTPUT = 512
const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

/**
 * Circular crop dialog (custom): the picked image sits under a dark, blurred surround with a
 * clear circular window showing the exact crop. Drag to reposition, zoom to scale; "Choose"
 * exports the circle's bounding box to a square PNG via canvas. Design-system throughout —
 * GlassSurface panel + color/type tokens.
 */
export function PhotoCropModal({
  image,
  onCancel,
  onConfirm
}: {
  image: string
  onCancel: () => void
  onConfirm: (dataUrl: string) => void | Promise<void>
}): React.JSX.Element {
  const imgRef = useRef<HTMLImageElement>(null)
  const [nat, setNat] = useState<{ w: number; h: number } | null>(null)
  const [zoom, setZoom] = useState(1)
  const [offset, setOffset] = useState({ x: 0, y: 0 })
  const [dragging, setDragging] = useState(false)
  const [error, setError] = useState(false)
  const [busy, setBusy] = useState(false)
  const drag = useRef<{ px: number; py: number; ox: number; oy: number } | null>(null)

  // base scale covers the circle (its shorter side fills it); effective = base × user zoom.
  const base = nat ? CIRCLE / Math.min(nat.w, nat.h) : 1
  const eff = base * zoom
  const dispW = nat ? nat.w * eff : 0
  const dispH = nat ? nat.h * eff : 0
  const maxX = Math.max(0, (dispW - CIRCLE) / 2)
  const maxY = Math.max(0, (dispH - CIRCLE) / 2)
  const imgLeft = (VIEWPORT - dispW) / 2 + offset.x
  const imgTop = (VIEWPORT - dispH) / 2 + offset.y

  // Escape closes; re-clamp the offset whenever the bounds shrink (zoom out / first load).
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onCancel()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onCancel])
  useEffect(() => {
    setOffset((o) => ({ x: clamp(o.x, -maxX, maxX), y: clamp(o.y, -maxY, maxY) }))
  }, [maxX, maxY])

  const onPointerDown = (e: React.PointerEvent): void => {
    if (error) return
    e.currentTarget.setPointerCapture(e.pointerId)
    drag.current = { px: e.clientX, py: e.clientY, ox: offset.x, oy: offset.y }
    setDragging(true)
  }
  const onPointerMove = (e: React.PointerEvent): void => {
    const d = drag.current
    if (!d) return
    setOffset({ x: clamp(d.ox + (e.clientX - d.px), -maxX, maxX), y: clamp(d.oy + (e.clientY - d.py), -maxY, maxY) })
  }
  const endDrag = (e: React.PointerEvent): void => {
    drag.current = null
    setDragging(false)
    try {
      e.currentTarget.releasePointerCapture(e.pointerId)
    } catch {
      /* already released */
    }
  }

  const choose = async (): Promise<void> => {
    const img = imgRef.current
    if (!img || !nat || busy) return
    const ctx = Object.assign(document.createElement('canvas'), { width: OUTPUT, height: OUTPUT }).getContext('2d')
    if (!ctx) return
    setBusy(true)
    // Map the circle's bounding box (viewport coords) back to source pixels via `eff`.
    const sx = (INSET - imgLeft) / eff
    const sy = (INSET - imgTop) / eff
    const sSize = CIRCLE / eff
    ctx.drawImage(img, sx, sy, sSize, sSize, 0, 0, OUTPUT, OUTPUT)
    await onConfirm(ctx.canvas.toDataURL('image/png'))
  }

  const surroundMask = `radial-gradient(circle ${RADIUS}px at center, transparent ${RADIUS}px, #000 ${RADIUS}px)`

  return createPortal(
    <div className={s.backdrop} onPointerDown={(e) => e.target === e.currentTarget && onCancel()}>
      <GlassSurface className={s.panel}>
        <span className={s.title}>Move and Scale</span>
        <div
          className={`${s.viewport}${dragging ? ` ${s.grabbing}` : ''}`}
          style={{ width: VIEWPORT, height: VIEWPORT }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={endDrag}
          onPointerCancel={endDrag}
        >
          <img
            ref={imgRef}
            src={image}
            alt=""
            draggable={false}
            onLoad={(e) => setNat({ w: e.currentTarget.naturalWidth, h: e.currentTarget.naturalHeight })}
            onError={() => setError(true)}
            style={{ position: 'absolute', left: imgLeft, top: imgTop, width: dispW, height: dispH, pointerEvents: 'none' }}
          />
          <div className={s.surround} style={{ backdropFilter: 'blur(1.5px) brightness(0.5)', WebkitBackdropFilter: 'blur(1.5px) brightness(0.5)', WebkitMaskImage: surroundMask, maskImage: surroundMask }} />
          <div className={s.ring} style={{ left: INSET, top: INSET, width: CIRCLE, height: CIRCLE }} />
        </div>
        {error ? (
          <span className={s.message}>Couldn’t load that image.</span>
        ) : (
          <input className={s.slider} type="range" min={1} max={4} step={0.01} value={zoom} onChange={(e) => setZoom(Number(e.target.value))} />
        )}
        <div className={s.actions}>
          <button className={s.button} onClick={onCancel} disabled={busy}>
            Cancel
          </button>
          <button className={s.buttonPrimary} onClick={() => void choose()} disabled={busy || !nat || error}>
            Choose
          </button>
        </div>
      </GlassSurface>
    </div>,
    document.body
  )
}
