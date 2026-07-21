import { useRef, useState } from 'react'
import { ProgressBar } from '../ProgressBar/ProgressBar'
import { GlassSegment } from '../../materials'
import * as s from './slider.css'

const decimalsOf = (step: number): number => {
  const str = String(step)
  return str.includes('.') ? str.split('.')[1].length : 0
}

/**
 * A pointer-driven value slider — the ProgressBar's accent-over-track fill with the Switch's glass
 * knob (GlassSegment over the label-control pill) riding the fill edge. Drafts locally while
 * dragging: `onInput` fires per-tick for live consumers, `onCommit` on release (and on an
 * arrow-key step) for the persisted write. `format` renders the live value readout after the strip.
 */
export function Slider({
  value,
  min,
  max,
  step = 1,
  ariaLabel,
  onCommit,
  onInput,
  format,
  readoutClassName,
}: {
  value: number
  min: number
  max: number
  step?: number
  ariaLabel: string
  onCommit: (v: number) => void
  onInput?: (v: number) => void
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
          const next = valueAt(e.clientX)
          setDraft(next)
          onInput?.(next)
        }}
        onPointerMove={(e) => {
          if (draft === null) return
          const next = valueAt(e.clientX)
          setDraft(next)
          onInput?.(next)
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
        <div className={s.knob} style={{ left: `${pct}%` }}>
          <GlassSegment style={{ borderRadius: 9 }}>
            <span className={s.knobFill} />
          </GlassSegment>
        </div>
      </div>
      {format && <span className={readoutClassName}>{format(v)}</span>}
    </>
  )
}
