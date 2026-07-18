import { useRef, useState } from 'react'
import { ProgressBar } from '../ProgressBar/ProgressBar'
import { frostMaterial } from '../../materials/glass-material'
import * as s from './slider.css'

const decimalsOf = (step: number): number => {
  const str = String(step)
  return str.includes('.') ? str.split('.')[1].length : 0
}

/**
 * A pointer-driven value slider — the ProgressBar's accent-over-track fill with a glass knob (the
 * shared frostMaterial recipe) riding the fill edge. Drafts locally while dragging; `onCommit`
 * fires on release (and on an arrow-key step), never per-tick. `format` renders the live value
 * readout after the strip.
 */
export function Slider({
  value,
  min,
  max,
  step = 1,
  ariaLabel,
  onCommit,
  format,
  readoutClassName,
}: {
  value: number
  min: number
  max: number
  step?: number
  ariaLabel: string
  onCommit: (v: number) => void
  format?: (v: number) => string
  readoutClassName?: string
}): React.JSX.Element {
  const [draft, setDraft] = useState<number | null>(null)
  const stripRef = useRef<HTMLDivElement>(null)
  const decimals = decimalsOf(step)
  const clamp = (v: number): number => Math.max(min, Math.min(max, v))
  const v = clamp(draft ?? value)
  const pct = ((v - min) / (max - min)) * 100
  const valueAt = (clientX: number): number => {
    const r = stripRef.current?.getBoundingClientRect()
    if (!r || r.width === 0) return v
    const t = Math.max(0, Math.min(1, (clientX - r.left) / r.width))
    return Number((Math.round((min + t * (max - min)) / step) * step).toFixed(decimals))
  }
  return (
    <>
      <div
        ref={stripRef}
        className={s.strip}
        role="slider"
        aria-label={ariaLabel}
        aria-valuemin={min}
        aria-valuemax={max}
        aria-valuenow={v}
        tabIndex={0}
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId)
          setDraft(valueAt(e.clientX))
        }}
        onPointerMove={(e) => {
          if (draft !== null) setDraft(valueAt(e.clientX))
        }}
        onPointerUp={() => {
          if (draft !== null && draft !== value) onCommit(draft)
          setDraft(null)
        }}
        onKeyDown={(e) => {
          if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
          e.preventDefault()
          const next = clamp(
            Number((value + (e.key === 'ArrowRight' ? step : -step)).toFixed(decimals)),
          )
          if (next !== value) onCommit(next)
        }}
      >
        <ProgressBar fill={pct / 100} />
        <div className={s.knob} style={{ ...frostMaterial, left: `${pct}%` }} />
      </div>
      {format && <span className={readoutClassName}>{format(v)}</span>}
    </>
  )
}
