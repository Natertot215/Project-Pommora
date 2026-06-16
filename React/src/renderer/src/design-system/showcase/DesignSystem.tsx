import { useEffect, useRef, useState, type ReactNode } from 'react'
import { vars, text, chip, chipColor, chipCheckbox } from '@renderer/design-system/tokens'
import { Icon, icons } from '@renderer/design-system/symbols'
import { GlassSurface } from '@renderer/design-system/materials/glass-surface'
import { GlassControls } from '@renderer/design-system/materials/glass-controls'

// camelCase / kebab-case key -> "Title Case" label.
function humanize(key: string): string {
  return key
    .replace(/[-_]/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/([a-zA-Z])(\d)/g, '$1 $2')
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

function rgbToHex(rgb: string): string {
  const m = rgb.match(/\d+(\.\d+)?/g)
  if (!m || m.length < 3) return rgb
  return (
    '#' +
    m
      .slice(0, 3)
      .map((n) => Math.round(Number(n)).toString(16).padStart(2, '0'))
      .join('')
      .toUpperCase()
  )
}

// Swatch reads its hex back from the rendered color, so it can't drift from the token.
function Swatch({ name, color }: { name: string; color: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [hex, setHex] = useState('')
  useEffect(() => {
    if (ref.current) setHex(rgbToHex(getComputedStyle(ref.current).backgroundColor))
  }, [])
  return (
    <div className="ds-swatch">
      <div ref={ref} className="ds-swatch-chip" style={{ background: color }} />
      <div className="ds-swatch-meta">
        <div className="ds-swatch-name">{name}</div>
        <div className="ds-swatch-hex">{hex}</div>
      </div>
    </div>
  )
}

// TypeRow reads size/weight back from the rendered sample (data-driven, no drift).
function TypeRow({ name, t }: { name: string; t: { standard: string; emphasized: string } }) {
  const ref = useRef<HTMLSpanElement>(null)
  const [meta, setMeta] = useState('')
  useEffect(() => {
    if (ref.current) {
      const cs = getComputedStyle(ref.current)
      setMeta(`${parseFloat(cs.fontSize)} / ${cs.fontWeight}`)
    }
  }, [])
  return (
    <div className="ds-type-row">
      <div className="ds-type-label">
        {name}
        <span className="ds-type-meta">{meta}</span>
      </div>
      <div className="ds-type-samples">
        <span ref={ref} className={t.standard}>
          {name}
        </span>
        <span className={t.emphasized}>{name}</span>
      </div>
    </div>
  )
}

const CHIP_SHAPES: Array<{ label: string; extra: string; content: (name: string) => ReactNode }> = [
  { label: 'Pill', extra: '', content: (n) => n },
  { label: 'Select', extra: '', content: () => <Icon name="circle-dashed" size={13} /> },
  {
    label: 'Checkbox',
    extra: chipCheckbox,
    content: () => <Icon name="check" size={12} strokeWidth={3} />
  }
]

const PENDING = [
  'Label',
  'Label · Segmented',
  'Button',
  'Button · Segmented',
  'Menu Item',
  'Menu Heading',
  'Separator'
]

export function DesignSystem() {
  const solids = Object.entries(vars.color.solid)
  const labels = Object.entries(vars.color.label)
  const ramp = Object.entries(text) as Array<[string, { standard: string; emphasized: string }]>
  const chipColors = Object.keys(chipColor) as Array<keyof typeof chipColor>
  const iconNames = Object.keys(icons) as Array<keyof typeof icons>

  return (
    <div className="ds-wrap">
      <header>
        <div className="ds-head">Pommora — Design System</div>
        <div className="ds-sub">
          Live from the source — every section reads the tokens / registries directly, so new colors,
          type styles, chips, and icons appear here automatically. <code>npm run showcase</code>.
        </div>
      </header>

      <section className="ds-section">
        <h2>Color · Solid spectrum</h2>
        <div className="ds-swatches">
          {solids.map(([n, c]) => (
            <Swatch key={n} name={humanize(n)} color={c} />
          ))}
        </div>
        <h2 style={{ marginTop: 28 }}>Color · Label tones</h2>
        <div className="ds-swatches">
          {labels.map(([n, c]) => (
            <Swatch key={n} name={humanize(n)} color={c} />
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Typography · Inter</h2>
        {ramp.map(([n, t]) => (
          <TypeRow key={n} name={humanize(n)} t={t} />
        ))}
      </section>

      <section className="ds-section">
        <h2>Chips · fill 60 · stroke 40 (2px, checkbox 1.5px) · text label-primary + 10%</h2>
        <div className="ds-chip-grid">
          {CHIP_SHAPES.map((shape) => (
            <div className="ds-chip-row" key={shape.label}>
              <div className="ds-chip-rowlabel">{shape.label}</div>
              {chipColors.map((k) => (
                <span
                  key={k}
                  className={`${chip} ${chipColor[k]}${shape.extra ? ' ' + shape.extra : ''}`}
                  title={k}
                >
                  {shape.content(humanize(k))}
                </span>
              ))}
            </div>
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Icons · Lucide ({iconNames.length}) — auto from the symbols registry</h2>
        <div className="ds-icon-grid">
          {iconNames.map((n) => (
            <div className="ds-icon-cell" key={n} title={n}>
              <Icon name={n} size={20} />
              <span className="ds-icon-name">{n}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Materials · Glass</h2>
        <div className="ds-mat-stage">
          <GlassSurface className="ds-mat-panel" style={{ borderRadius: 16 }}>
            <span className="ds-mat-label">GlassSurface</span>
          </GlassSurface>
          <GlassControls className="ds-mat-panel" style={{ borderRadius: 16 }}>
            <span className="ds-mat-label">GlassControls</span>
          </GlassControls>
        </div>
        <div className="ds-mat-note">
          liquidGL "Tinted Lens" — blur 5 · brightness 90%. Identical for now, separable later. Full
          comparison at <code>/glass-lab.html</code>.
        </div>
      </section>

      <section className="ds-section">
        <h2>Components · pending React build (in Figma)</h2>
        <div className="ds-pending">
          {PENDING.map((x) => (
            <span key={x}>{x}</span>
          ))}
        </div>
      </section>
    </div>
  )
}
