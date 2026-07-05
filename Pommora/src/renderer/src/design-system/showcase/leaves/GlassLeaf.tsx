import { useState, type CSSProperties, type Dispatch, type SetStateAction } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useIsCompact } from './helpers'

// Materials · Glass — a live tuner for the Pommora CSS frost. A param-driven glass
// panel over a switchable backdrop, with the knobs as a side rail on desktop and a
// dropdown on a compact screen. "Window" / "Surface" / "Control" restore the three
// material presets (identical today — all are `frostMaterial` — but distinct slots
// ready to diverge, mirroring GlassWindow / GlassSurface / GlassControls).

type FrostParams = {
  blur: number
  brightness: number
  borderAlpha: number
  specular: number
  ring: number
  glowBlur: number
  glowAlpha: number
  shadowY: number
  shadowBlur: number
  shadowAlpha: number
}

// The shipped frost recipe (mirrors materials/glass-material.ts), expressed as knobs.
const FROST: FrostParams = {
  blur: 6,
  brightness: 95,
  borderAlpha: 12,
  specular: 35,
  ring: 8,
  glowBlur: 12,
  glowAlpha: 8,
  shadowY: 8,
  shadowBlur: 26,
  shadowAlpha: 28
}
const PRESETS: Record<string, FrostParams> = { Window: FROST, Surface: FROST, Control: FROST }

const SURFACES = [
  { key: 'philly', img: '/surfaces/philly.jpg' },
  { key: 'forest', img: '/surfaces/forest.jpg' },
  { key: 'mac', img: '/surfaces/mac.png' },
  { key: 'app dark', img: '' }
] as const

type Ctl = { key: keyof FrostParams; label: string; min: number; max: number; step: number; unit: string }
const CONTROLS: Ctl[] = [
  { key: 'blur', label: 'Blur', min: 0, max: 30, step: 0.5, unit: 'px' },
  { key: 'brightness', label: 'Brightness', min: 70, max: 130, step: 1, unit: '%' },
  { key: 'borderAlpha', label: 'Edge', min: 0, max: 60, step: 1, unit: '%' },
  { key: 'specular', label: 'Top rim', min: 0, max: 90, step: 1, unit: '%' },
  { key: 'ring', label: 'Inner ring', min: 0, max: 40, step: 1, unit: '%' },
  { key: 'glowAlpha', label: 'Edge glow', min: 0, max: 40, step: 1, unit: '%' },
  { key: 'glowBlur', label: 'Glow reach', min: 2, max: 30, step: 1, unit: 'px' },
  { key: 'shadowY', label: 'Shadow Y', min: 0, max: 30, step: 1, unit: 'px' },
  { key: 'shadowBlur', label: 'Shadow blur', min: 0, max: 50, step: 1, unit: 'px' },
  { key: 'shadowAlpha', label: 'Shadow', min: 0, max: 60, step: 1, unit: '%' }
]

// Glass highlights are white light / black shade — pure #FFFFFF / #000000, not the
// off-white system primitive (matching the shipped frost material).
function hexA(hex6: string, pct: number): string {
  const a = Math.round((Math.max(0, Math.min(100, pct)) / 100) * 255)
  return hex6 + a.toString(16).padStart(2, '0').toUpperCase()
}

function buildGlassStyle(p: FrostParams): CSSProperties {
  const bf = `blur(${p.blur}px) brightness(${p.brightness}%)`
  const shadow = [
    `inset 0 1px 0 ${hexA('#FFFFFF', p.specular)}`,
    p.ring > 0 ? `inset 0 0 0 1px ${hexA('#FFFFFF', p.ring)}` : '',
    p.glowAlpha > 0 ? `inset 0 -${p.glowBlur}px ${Math.round(p.glowBlur * 1.5)}px -${p.glowBlur}px ${hexA('#FFFFFF', p.glowAlpha)}` : '',
    `0 ${p.shadowY}px ${p.shadowBlur}px ${hexA('#000000', p.shadowAlpha)}`
  ]
    .filter(Boolean)
    .join(', ')
  return {
    background: 'transparent',
    backdropFilter: bf,
    WebkitBackdropFilter: bf,
    border: `1px solid ${hexA('#FFFFFF', p.borderAlpha)}`,
    boxShadow: shadow
  }
}

function ControlsBody({ params, setParams }: { params: FrostParams; setParams: Dispatch<SetStateAction<FrostParams>> }): React.JSX.Element {
  return (
    <div className="gl-panel-body">
      <div className="gl-presets">
        <span className="gl-presets-label">Restore preset</span>
        {Object.keys(PRESETS).map((name) => (
          <button key={name} type="button" className="gl-preset-btn" onClick={() => setParams(PRESETS[name])}>
            {name}
          </button>
        ))}
      </div>
      {CONTROLS.map((c) => (
        <label className="gl-ctl" key={c.key}>
          <span className="gl-ctl-label">{c.label}</span>
          <input
            type="range"
            min={c.min}
            max={c.max}
            step={c.step}
            value={params[c.key]}
            onChange={(e) => setParams((p) => ({ ...p, [c.key]: Number(e.target.value) }))}
          />
          <span className="gl-ctl-val">
            {params[c.key]}
            {c.unit}
          </span>
        </label>
      ))}
    </div>
  )
}

// Controls surface: an always-open side rail on desktop, a toggled dropdown on compact.
function GlassControls({ params, setParams }: { params: FrostParams; setParams: Dispatch<SetStateAction<FrostParams>> }): React.JSX.Element {
  const compact = useIsCompact()
  const [open, setOpen] = useState(false)
  if (!compact) {
    return (
      <aside className="gl-controls gl-controls-rail">
        <div className="gl-controls-title">Glass controls</div>
        <ControlsBody params={params} setParams={setParams} />
      </aside>
    )
  }
  return (
    <div className="gl-controls gl-controls-drop">
      <button type="button" className="gl-controls-toggle" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
        <span>Glass controls</span>
        <Icon name={open ? 'chevron-up' : 'chevron-down'} size={14} />
      </button>
      {open && <ControlsBody params={params} setParams={setParams} />}
    </div>
  )
}

export function GlassLeaf(): React.JSX.Element {
  const [params, setParams] = useState<FrostParams>(PRESETS.Window)
  const [bg, setBg] = useState<(typeof SURFACES)[number]>(SURFACES[0])
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Materials · Glass</h2>
        <div className="gl-tuner">
          <div className="gl-preview-wrap">
            <div className="gl-switch">
              {SURFACES.map((x) => (
                <button key={x.key} type="button" className={'gl-sw' + (x.key === bg.key ? ' is-on' : '')} onClick={() => setBg(x)}>
                  {x.key}
                </button>
              ))}
            </div>
            <div className={'gl-preview' + (bg.img === '' ? ' is-dark' : '')} style={bg.img ? { backgroundImage: `url(${bg.img})` } : undefined}>
              <div className="gl-glass" style={buildGlassStyle(params)}>
                <span className="gl-glass-label">Glass</span>
              </div>
            </div>
          </div>
          <GlassControls params={params} setParams={setParams} />
        </div>
      </section>
    </div>
  )
}
