import { useState } from 'react'
import {
  CONTROL_KNOBS,
  useControlOptics,
  setControlOptic
} from '@renderer/design-system/materials/control-optics'
import './glass-optics-sliders.css'

/**
 * Live tuner for the control-glass optics — bound straight to the store that
 * GlassControls renders, so a drag updates the real toolbar glass instantly.
 * Copy dumps the current values for pasting into control-optics.ts. Homepage-only.
 */
export function GlassOpticsSliders(): React.JSX.Element {
  const optics = useControlOptics()
  const [copied, setCopied] = useState(false)

  const copy = (): void => {
    void navigator.clipboard
      .writeText(JSON.stringify(optics, null, 2))
      .then(() => {
        setCopied(true)
        setTimeout(() => setCopied(false), 1200)
      })
      .catch(() => undefined)
  }

  return (
    <div className="glass-optics-sliders">
      <div className="gos-head">
        <span className="gos-title">Control glass optics</span>
        <button type="button" className="gos-copy" onClick={copy}>
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <div className="gos-grid">
        {CONTROL_KNOBS.map((k) => {
          const v = Number(optics[k.key] ?? 0)
          return (
            <label key={k.key} className="gos-row">
              <span className="gos-label">{k.label}</span>
              <input
                type="range"
                min={k.min}
                max={k.max}
                step={k.step}
                value={v}
                onChange={(e) => setControlOptic(k.key, Number(e.target.value))}
              />
              <span className="gos-val">{k.step < 1 ? v.toFixed(2) : v.toFixed(0)}</span>
            </label>
          )
        })}
      </div>
    </div>
  )
}
