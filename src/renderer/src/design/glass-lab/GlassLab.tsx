import { useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react'
import LiquidGlass from 'liquid-glass-react'

const PANEL_W = 200
const PANEL_H = 110

// --- shared bits ----------------------------------------------------------

function Slider({
  label,
  value,
  min,
  max,
  step = 1,
  unit = '',
  onChange
}: {
  label: string
  value: number
  min: number
  max: number
  step?: number
  unit?: string
  onChange: (v: number) => void
}) {
  return (
    <label className="gl-ctrl">
      <span className="gl-ctrl-label">{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
      <span className="gl-ctrl-val">
        {value}
        {unit}
      </span>
    </label>
  )
}

/**
 * A stage with three side-by-side fields — rainbow · aerial forest · Pommora
 * window background — and a draggable glass element you can slide across them.
 */
function GlassStage({ children }: { children: ReactNode }) {
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

function GlassCard({
  title,
  blurb,
  source,
  stage,
  controls
}: {
  title: string
  blurb: string
  source: { label: string; url: string }
  stage: ReactNode
  controls: ReactNode
}) {
  return (
    <div className="gl-card">
      <div className="gl-card-head">
        <div>
          <div className="gl-card-title">{title}</div>
          <div className="gl-card-blurb">{blurb}</div>
        </div>
        <a className="gl-card-src" href={source.url} target="_blank" rel="noreferrer">
          {source.label} ↗
        </a>
      </div>
      {stage}
      <div className="gl-controls">{controls}</div>
    </div>
  )
}

function PanelLabel({ children }: { children: ReactNode }) {
  return <span className="gl-panel-label">{children}</span>
}

// --- 1. liquid-glass-react (rdev / Max Rovensky) --------------------------

const MODES = ['standard', 'polar', 'prominent', 'shader'] as const

function PanelLiquidGlassReact() {
  const [displacement, setDisplacement] = useState(64)
  const [blur, setBlur] = useState(0.1)
  const [saturation, setSaturation] = useState(130)
  const [aberration, setAberration] = useState(2)
  const [elasticity, setElasticity] = useState(0.3)
  const [radius, setRadius] = useState(28)
  const [mode, setMode] = useState<(typeof MODES)[number]>('standard')
  return (
    <GlassCard
      title="liquid-glass-react"
      blurb="SVG displacement library — the installed npm package"
      source={{ label: 'rdev/liquid-glass-react', url: 'https://github.com/rdev/liquid-glass-react' }}
      stage={
        <GlassStage>
          <LiquidGlass
            displacementScale={displacement}
            blurAmount={blur}
            saturation={saturation}
            aberrationIntensity={aberration}
            elasticity={elasticity}
            cornerRadius={radius}
            mode={mode}
            padding="0px"
          >
            <div className="gl-panel-fixed">
              <PanelLabel>Liquid Glass</PanelLabel>
            </div>
          </LiquidGlass>
        </GlassStage>
      }
      controls={
        <>
          <Slider label="Displace" value={displacement} min={0} max={200} onChange={setDisplacement} />
          <Slider label="Blur" value={blur} min={0} max={1} step={0.02} onChange={setBlur} />
          <Slider label="Saturate" value={saturation} min={100} max={220} unit="%" onChange={setSaturation} />
          <Slider label="Aberration" value={aberration} min={0} max={12} onChange={setAberration} />
          <Slider label="Elasticity" value={elasticity} min={0} max={1} step={0.05} onChange={setElasticity} />
          <Slider label="Radius" value={radius} min={0} max={60} unit="px" onChange={setRadius} />
          <label className="gl-ctrl">
            <span className="gl-ctrl-label">Mode</span>
            <select value={mode} onChange={(e) => setMode(e.target.value as (typeof MODES)[number])}>
              {MODES.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </select>
          </label>
        </>
      }
    />
  )
}

// --- 2. SVG turbulence displacement (rizroze / nikdelvin technique) -------

function PanelSvgDisplacement() {
  const [freq, setFreq] = useState(9)
  const [scale, setScale] = useState(120)
  const [blur, setBlur] = useState(2)
  const fid = 'gl-svg-disp'
  return (
    <GlassCard
      title="SVG Turbulence Displacement"
      blurb="Zero-dep backdrop-filter: url() refraction — Chromium only"
      source={{ label: 'rizroze/liquid-glass', url: 'https://github.com/rizroze/liquid-glass' }}
      stage={
        <GlassStage>
          <svg className="gl-svg-defs" aria-hidden="true">
            <filter id={fid} x="-30%" y="-30%" width="160%" height="160%">
              <feTurbulence
                type="fractalNoise"
                baseFrequency={freq / 1000}
                numOctaves={2}
                seed={11}
                result="n"
              />
              <feDisplacementMap
                in="SourceGraphic"
                in2="n"
                scale={scale}
                xChannelSelector="R"
                yChannelSelector="G"
              />
            </filter>
          </svg>
          <div
            className="gl-panel"
            style={{
              backdropFilter: `blur(${blur}px) url(#${fid})`,
              WebkitBackdropFilter: `blur(${blur}px)`,
              borderRadius: 24,
              border: '1px solid rgba(255,255,255,0.16)'
            }}
          >
            <PanelLabel>SVG Displace</PanelLabel>
          </div>
        </GlassStage>
      }
      controls={
        <>
          <Slider label="Frequency" value={freq} min={1} max={30} onChange={setFreq} />
          <Slider label="Displace" value={scale} min={0} max={300} onChange={setScale} />
          <Slider label="Blur" value={blur} min={0} max={16} unit="px" onChange={setBlur} />
        </>
      }
    />
  )
}

// --- 3. CSS Backdrop Frost (Apple "Regular") ------------------------------

function PanelFrost() {
  const [blur, setBlur] = useState(8)
  const [sat, setSat] = useState(140)
  const [bright, setBright] = useState(108)
  const [rim, setRim] = useState(22)
  const [radius, setRadius] = useState(24)
  return (
    <GlassCard
      title="CSS Backdrop Frost"
      blurb="backdrop blur + saturate + specular edges (Apple Regular)"
      source={{
        label: 'Apple · Liquid Glass',
        url: 'https://developer.apple.com/documentation/technologyoverviews/liquid-glass'
      }}
      stage={
        <GlassStage>
          <div
            className="gl-panel"
            style={{
              backdropFilter: `blur(${blur}px) saturate(${sat}%) brightness(${bright}%)`,
              WebkitBackdropFilter: `blur(${blur}px) saturate(${sat}%) brightness(${bright}%)`,
              background: 'transparent',
              borderRadius: radius,
              border: '0.5px solid rgba(255,255,255,0.14)',
              boxShadow: `inset 0 1px 0 rgba(255,255,255,${rim / 100}), inset 0 0 18px -6px rgba(255,255,255,0.3), inset 0 0 0 0.5px rgba(0,0,0,0.2), 0 6px 22px rgba(0,0,0,0.22)`
            }}
          >
            <PanelLabel>Frost</PanelLabel>
          </div>
        </GlassStage>
      }
      controls={
        <>
          <Slider label="Blur" value={blur} min={0} max={30} unit="px" onChange={setBlur} />
          <Slider label="Saturate" value={sat} min={100} max={220} unit="%" onChange={setSat} />
          <Slider label="Brightness" value={bright} min={80} max={140} unit="%" onChange={setBright} />
          <Slider label="Edge rim" value={rim} min={0} max={60} unit="%" onChange={setRim} />
          <Slider label="Radius" value={radius} min={0} max={60} unit="px" onChange={setRadius} />
        </>
      }
    />
  )
}

// --- 4. Classic Glassmorphism (ui.glass) ----------------------------------

function PanelGlassmorphism() {
  const [blur, setBlur] = useState(10)
  const [fill, setFill] = useState(16)
  const [border, setBorder] = useState(22)
  const [sat, setSat] = useState(120)
  const [radius, setRadius] = useState(20)
  return (
    <GlassCard
      title="Classic Glassmorphism"
      blurb="Translucent white fill + blur + border (the 'frosted card')"
      source={{ label: 'ui.glass', url: 'https://ui.glass/' }}
      stage={
        <GlassStage>
          <div
            className="gl-panel"
            style={{
              backdropFilter: `blur(${blur}px) saturate(${sat}%)`,
              WebkitBackdropFilter: `blur(${blur}px) saturate(${sat}%)`,
              background: `rgba(255,255,255,${fill / 100})`,
              borderRadius: radius,
              border: `1px solid rgba(255,255,255,${border / 100})`,
              boxShadow: '0 8px 30px rgba(0,0,0,0.25)'
            }}
          >
            <PanelLabel>Glassmorphism</PanelLabel>
          </div>
        </GlassStage>
      }
      controls={
        <>
          <Slider label="Blur" value={blur} min={0} max={30} unit="px" onChange={setBlur} />
          <Slider label="Fill" value={fill} min={0} max={50} unit="%" onChange={setFill} />
          <Slider label="Border" value={border} min={0} max={60} unit="%" onChange={setBorder} />
          <Slider label="Saturate" value={sat} min={100} max={220} unit="%" onChange={setSat} />
          <Slider label="Radius" value={radius} min={0} max={60} unit="px" onChange={setRadius} />
        </>
      }
    />
  )
}

// --- 5. Specular Bevel (macOS recreation) ---------------------------------

function PanelSpecular() {
  const [blur, setBlur] = useState(6)
  const [rim, setRim] = useState(40)
  const [glow, setGlow] = useState(26)
  const [tint, setTint] = useState(8)
  const [radius, setRadius] = useState(26)
  return (
    <GlassCard
      title="Specular Bevel"
      blurb="Edge-lit bevel: bright rim + dark containment + inner glow"
      source={{
        label: 'lucasromerodb/liquid-glass-effect-macos',
        url: 'https://github.com/lucasromerodb/liquid-glass-effect-macos'
      }}
      stage={
        <GlassStage>
          <div
            className="gl-panel"
            style={{
              backdropFilter: `blur(${blur}px)`,
              WebkitBackdropFilter: `blur(${blur}px)`,
              background: `rgba(255,255,255,${tint / 100})`,
              borderRadius: radius,
              boxShadow: `inset 0 1.5px 0 rgba(255,255,255,${rim / 100}), inset 0 0 22px -4px rgba(255,255,255,${glow / 100}), inset 0 -2px 6px -2px rgba(0,0,0,0.35), inset 0 0 0 1px rgba(0,0,0,0.18), 0 10px 30px rgba(0,0,0,0.3)`
            }}
          >
            <PanelLabel>Specular</PanelLabel>
          </div>
        </GlassStage>
      }
      controls={
        <>
          <Slider label="Blur" value={blur} min={0} max={30} unit="px" onChange={setBlur} />
          <Slider label="Rim" value={rim} min={0} max={80} unit="%" onChange={setRim} />
          <Slider label="Inner glow" value={glow} min={0} max={60} unit="%" onChange={setGlow} />
          <Slider label="Tint" value={tint} min={0} max={30} unit="%" onChange={setTint} />
          <Slider label="Radius" value={radius} min={0} max={60} unit="px" onChange={setRadius} />
        </>
      }
    />
  )
}

// --- 6. Tinted Lens (liquidGL / shader-style) -----------------------------

function PanelTintedLens() {
  const [blur, setBlur] = useState(4)
  const [hue, setHue] = useState(210)
  const [strength, setStrength] = useState(26)
  const [bright, setBright] = useState(112)
  const [radius, setRadius] = useState(24)
  return (
    <GlassCard
      title="Tinted Lens"
      blurb="Colored lens tint + blur (WebGL-style approximation)"
      source={{ label: 'naughtyduk/liquidGL', url: 'https://github.com/naughtyduk/liquidGL' }}
      stage={
        <GlassStage>
          <div
            className="gl-panel"
            style={{
              backdropFilter: `blur(${blur}px) brightness(${bright}%)`,
              WebkitBackdropFilter: `blur(${blur}px) brightness(${bright}%)`,
              background: `radial-gradient(120% 120% at 30% 20%, hsla(${hue}, 90%, 60%, ${strength / 100}), hsla(${(hue + 60) % 360}, 90%, 55%, ${strength / 200}) 60%, transparent)`,
              borderRadius: radius,
              border: '1px solid rgba(255,255,255,0.16)',
              boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.25), 0 8px 26px rgba(0,0,0,0.28)'
            }}
          >
            <PanelLabel>Tinted Lens</PanelLabel>
          </div>
        </GlassStage>
      }
      controls={
        <>
          <Slider label="Blur" value={blur} min={0} max={30} unit="px" onChange={setBlur} />
          <Slider label="Hue" value={hue} min={0} max={360} onChange={setHue} />
          <Slider label="Strength" value={strength} min={0} max={60} unit="%" onChange={setStrength} />
          <Slider label="Brightness" value={bright} min={80} max={140} unit="%" onChange={setBright} />
          <Slider label="Radius" value={radius} min={0} max={60} unit="px" onChange={setRadius} />
        </>
      }
    />
  )
}

// --- page -----------------------------------------------------------------

export function GlassLab() {
  return (
    <div className="gl-wrap">
      <header className="gl-head">
        <div className="gl-title">Liquid Glass Lab</div>
        <div className="gl-sub">
          Six glass approaches, each over three fields — <b>rainbow</b> · <b>aerial forest</b> ·
          Pommora&apos;s <b>window background</b>. Drag any panel across the fields, and tune it with
          the sliders. The two displacement effects (1 &amp; 2) need a Chromium browser
          (Chrome/Electron) to show real refraction.
        </div>
      </header>
      <div className="gl-grid">
        <PanelLiquidGlassReact />
        <PanelSvgDisplacement />
        <PanelFrost />
        <PanelGlassmorphism />
        <PanelSpecular />
        <PanelTintedLens />
      </div>
    </div>
  )
}
