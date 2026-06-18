import {
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode
} from 'react'
import { EdgeLensGlass } from '@renderer/design-system/materials'
import './glass-editor.css'

// Live editor: a custom CSS liquid-glass component side-by-side with the Apple edge-lens
// (SVG refraction). Both share size + radius so it's a fair comparison; each has its own
// knobs. The CSS one emits a copyable rule; the Apple one is SVG (no pure-CSS snippet).

const SURFACES = [
  { key: 'philly', img: '/surfaces/philly.jpg' },
  { key: 'forest', img: '/surfaces/forest.jpg' },
  { key: 'mac', img: '/surfaces/mac.png' },
  { key: 'app dark', img: '' }
] as const

type State = {
  // shared
  width: number
  height: number
  radius: number
  // CSS frost
  blur: number
  saturate: number
  brightness: number
  contrast: number
  fillColor: string
  fillAlpha: number
  borderColor: string
  borderAlpha: number
  borderWidth: number
  specular: number
  ring: number
  glowBlur: number
  glowAlpha: number
  shadowY: number
  shadowBlur: number
  shadowAlpha: number
  // Apple edge-lens
  eScale: number
  eBevel: number
  eBlur: number
  eSaturate: number
  eAberration: number
  eSpecular: number
}

// Apple's canonical default edge-lens recipe — a fixed reference (not tunable).
const APPLE_DEFAULT = { scale: 40, bevel: 20, blur: 2.5, saturate: 132, aberration: 3, specular: 0.34 }

const INITIAL: State = {
  width: 256,
  height: 160,
  radius: 24,
  blur: 6,
  saturate: 100,
  brightness: 95,
  contrast: 100,
  fillColor: '#FFFFFF',
  fillAlpha: 0,
  borderColor: '#FFFFFF',
  borderAlpha: 12,
  borderWidth: 1,
  specular: 50,
  ring: 12,
  glowBlur: 12,
  glowAlpha: 14,
  shadowY: 8,
  shadowBlur: 26,
  shadowAlpha: 28,
  eScale: 30,
  eBevel: 22,
  eBlur: 5,
  eSaturate: 125,
  eAberration: 2,
  eSpecular: 30
}

function hexA(hex6: string, pct: number): string {
  const a = Math.round((Math.max(0, Math.min(100, pct)) / 100) * 255)
  return hex6.toUpperCase() + a.toString(16).padStart(2, '0').toUpperCase()
}

function buildDecls(s: State): string {
  const bf = `blur(${s.blur}px) saturate(${s.saturate}%) brightness(${s.brightness}%) contrast(${s.contrast}%)`
  const shadow = [
    `inset 0 1px 0 ${hexA('#FFFFFF', s.specular)}`, // top specular
    s.ring > 0 ? `inset 0 0 0 1px ${hexA('#FFFFFF', s.ring)}` : '', // hairline inner ring
    s.glowAlpha > 0 ? `inset 0 -${s.glowBlur}px ${Math.round(s.glowBlur * 1.5)}px -${s.glowBlur}px ${hexA('#FFFFFF', s.glowAlpha)}` : '', // lower-rim light
    `0 ${s.shadowY}px ${s.shadowBlur}px ${hexA('#000000', s.shadowAlpha)}`
  ]
    .filter(Boolean)
    .join(', ')
  return [
    `width: ${s.width}px;`,
    `height: ${s.height}px;`,
    `border-radius: ${s.radius}px;`,
    `background: ${hexA(s.fillColor, s.fillAlpha)};`,
    `backdrop-filter: ${bf};`,
    `-webkit-backdrop-filter: ${bf};`,
    `border: ${s.borderWidth}px solid ${hexA(s.borderColor, s.borderAlpha)};`,
    `box-shadow: ${shadow};`
  ].join('\n  ')
}

type Ctl = { key: keyof State; label: string; min: number; max: number; step: number; unit?: string }
const SECTIONS: { title: string; controls: Ctl[] }[] = [
  {
    title: 'Size · shared',
    controls: [
      { key: 'width', label: 'Width', min: 100, max: 460, step: 1, unit: 'px' },
      { key: 'height', label: 'Height', min: 60, max: 320, step: 1, unit: 'px' },
      { key: 'radius', label: 'Radius', min: 0, max: 60, step: 1, unit: 'px' }
    ]
  },
  {
    title: 'CSS frost · backdrop',
    controls: [
      { key: 'blur', label: 'Blur', min: 0, max: 40, step: 0.5, unit: 'px' },
      { key: 'saturate', label: 'Saturate', min: 100, max: 220, step: 1, unit: '%' },
      { key: 'brightness', label: 'Brightness', min: 70, max: 130, step: 1, unit: '%' },
      { key: 'contrast', label: 'Contrast', min: 80, max: 140, step: 1, unit: '%' }
    ]
  },
  { title: 'CSS frost · fill', controls: [{ key: 'fillAlpha', label: 'Fill', min: 0, max: 50, step: 1, unit: '%' }] },
  {
    title: 'CSS frost · edge',
    controls: [
      { key: 'borderWidth', label: 'Width', min: 0, max: 3, step: 0.5, unit: 'px' },
      { key: 'borderAlpha', label: 'Opacity', min: 0, max: 80, step: 1, unit: '%' }
    ]
  },
  {
    title: 'CSS frost · glassy edge',
    controls: [
      { key: 'specular', label: 'Top rim', min: 0, max: 90, step: 1, unit: '%' },
      { key: 'ring', label: 'Inner ring', min: 0, max: 60, step: 1, unit: '%' },
      { key: 'glowAlpha', label: 'Edge glow', min: 0, max: 60, step: 1, unit: '%' },
      { key: 'glowBlur', label: 'Glow reach', min: 2, max: 40, step: 1, unit: 'px' }
    ]
  },
  {
    title: 'CSS frost · shadow',
    controls: [
      { key: 'shadowY', label: 'Offset Y', min: 0, max: 40, step: 1, unit: 'px' },
      { key: 'shadowBlur', label: 'Blur', min: 0, max: 60, step: 1, unit: 'px' },
      { key: 'shadowAlpha', label: 'Opacity', min: 0, max: 60, step: 1, unit: '%' }
    ]
  },
  {
    title: 'Apple edge-lens',
    controls: [
      { key: 'eScale', label: 'Refraction', min: 0, max: 90, step: 1, unit: 'px' },
      { key: 'eBevel', label: 'Rim width', min: 4, max: 48, step: 1, unit: 'px' },
      { key: 'eBlur', label: 'Blur', min: 0, max: 16, step: 0.5, unit: 'px' },
      { key: 'eSaturate', label: 'Saturate', min: 100, max: 180, step: 1, unit: '%' },
      { key: 'eAberration', label: 'Aberration', min: 0, max: 12, step: 0.5, unit: 'px' },
      { key: 'eSpecular', label: 'Specular', min: 0, max: 70, step: 1, unit: '%' }
    ]
  }
]

function Draggable({ initialX, initialY, children }: { initialX: number; initialY: number; children: ReactNode }): React.JSX.Element {
  const [pos, setPos] = useState({ x: initialX, y: initialY })
  const drag = useRef({ active: false, sx: 0, sy: 0, ox: 0, oy: 0 })
  const onDown = (e: ReactPointerEvent<HTMLDivElement>): void => {
    drag.current = { active: true, sx: e.clientX, sy: e.clientY, ox: pos.x, oy: pos.y }
    e.currentTarget.setPointerCapture(e.pointerId)
  }
  const onMove = (e: ReactPointerEvent<HTMLDivElement>): void => {
    if (!drag.current.active) return
    setPos({ x: drag.current.ox + (e.clientX - drag.current.sx), y: drag.current.oy + (e.clientY - drag.current.sy) })
  }
  const onUp = (): void => {
    drag.current.active = false
  }
  return (
    <div className="ge-float" style={{ left: pos.x, top: pos.y }} onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} title="Drag me">
      {children}
    </div>
  )
}

export function GlassEditor(): React.JSX.Element {
  const [s, setS] = useState<State>(INITIAL)
  const [custom, setCustom] = useState('')
  const [bg, setBg] = useState<(typeof SURFACES)[number]>(SURFACES[0])
  const [copied, setCopied] = useState(false)

  const set = (key: keyof State, v: number | string): void => setS((p) => ({ ...p, [key]: v }))
  const decls = useMemo(() => buildDecls(s), [s])
  const fullCss = `#ge-glass {\n  ${decls}${custom.trim() ? '\n  ' + custom.trim() : ''}\n}`

  const copy = (): void => {
    void navigator.clipboard.writeText(fullCss).then(() => {
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1200)
    })
  }

  const isApp = bg.img === ''
  const gap = 44
  const x0 = 36
  const x1 = x0 + s.width + gap
  const x2 = x1 + s.width + gap

  return (
    <div className="ge-wrap">
      <style>{fullCss}</style>
      <div className={'ge-stage' + (isApp ? ' is-app' : '')} style={isApp ? undefined : { backgroundImage: `url(${bg.img})` }}>
        <div className="ge-switch">
          {SURFACES.map((x) => (
            <button key={x.key} type="button" className={'ge-sw' + (x.key === bg.key ? ' is-on' : '')} onClick={() => setBg(x)}>
              {x.key}
            </button>
          ))}
        </div>

        <Draggable initialX={x0} initialY={150}>
          <div id="ge-glass">
            <span className="ge-glass-label">CSS frost</span>
          </div>
        </Draggable>

        <Draggable initialX={x1} initialY={150}>
          <div className="ge-apple" style={{ width: s.width, height: s.height, borderRadius: s.radius }}>
            <EdgeLensGlass
              width={s.width}
              height={s.height}
              radius={s.radius}
              scale={s.eScale}
              bevel={s.eBevel}
              blur={s.eBlur}
              saturate={s.eSaturate}
              aberration={s.eAberration}
              specular={s.eSpecular / 100}
            />
            <span className="ge-glass-label ge-apple-label">Apple (tuned)</span>
          </div>
        </Draggable>

        <Draggable initialX={x2} initialY={150}>
          <div className="ge-apple" style={{ width: s.width, height: s.height, borderRadius: s.radius }}>
            <EdgeLensGlass
              width={s.width}
              height={s.height}
              radius={s.radius}
              scale={APPLE_DEFAULT.scale}
              bevel={APPLE_DEFAULT.bevel}
              blur={APPLE_DEFAULT.blur}
              saturate={APPLE_DEFAULT.saturate}
              aberration={APPLE_DEFAULT.aberration}
              specular={APPLE_DEFAULT.specular}
            />
            <span className="ge-glass-label ge-apple-label">Apple default</span>
          </div>
        </Draggable>
      </div>

      <aside className="ge-rail">
        <div className="ge-head">
          <div className="ge-title">CSS frost vs. Apple</div>
          <button type="button" className="ge-reset" onClick={() => setS(INITIAL)}>
            Reset
          </button>
        </div>

        {SECTIONS.map((sec) => (
          <div className="ge-section" key={sec.title}>
            <div className="ge-section-title">{sec.title}</div>
            {sec.title === 'CSS frost · fill' && (
              <label className="ge-ctl ge-ctl-color">
                <span className="ge-ctl-label">Color</span>
                <input type="color" value={s.fillColor} onChange={(e) => set('fillColor', e.target.value)} />
                <span className="ge-ctl-val">{s.fillColor.toUpperCase()}</span>
              </label>
            )}
            {sec.title === 'CSS frost · edge' && (
              <label className="ge-ctl ge-ctl-color">
                <span className="ge-ctl-label">Color</span>
                <input type="color" value={s.borderColor} onChange={(e) => set('borderColor', e.target.value)} />
                <span className="ge-ctl-val">{s.borderColor.toUpperCase()}</span>
              </label>
            )}
            {sec.controls.map((c) => (
              <label className="ge-ctl" key={c.key}>
                <span className="ge-ctl-label">{c.label}</span>
                <input type="range" min={c.min} max={c.max} step={c.step} value={s[c.key] as number} onChange={(e) => set(c.key, Number(e.target.value))} />
                <span className="ge-ctl-val">
                  {s[c.key] as number}
                  {c.unit ?? ''}
                </span>
              </label>
            ))}
          </div>
        ))}

        <div className="ge-section">
          <div className="ge-section-title">
            CSS frost — generated CSS
            <button type="button" className="ge-copy" onClick={copy}>
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
          <pre className="ge-css">{fullCss}</pre>
          <div className="ge-note">The Apple edge-lens is SVG-based, so it has no pure-CSS snippet — it lives in the design system as a component.</div>
        </div>

        <div className="ge-section">
          <div className="ge-section-title">CSS frost — custom CSS (live)</div>
          <textarea
            className="ge-custom"
            spellCheck={false}
            placeholder={'e.g.\nbackground: linear-gradient(#FFFFFF14, #FFFFFF05);'}
            value={custom}
            onChange={(e) => setCustom(e.target.value)}
          />
        </div>
      </aside>
    </div>
  )
}
