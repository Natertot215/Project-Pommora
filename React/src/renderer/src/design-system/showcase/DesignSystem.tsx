import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import { vars, text, chip, chipColor, chipCheckbox } from '@renderer/design-system/tokens'
import { Icon, icons } from '@renderer/design-system/symbols'
import { GlassStage } from './GlassStage'

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

type RampStyle = { standard: string; emphasized: string }

// Read a value back from a rendered node on mount — so the showcase shows the
// real computed value and can't drift from the token. Shared by Swatch + TypeEntry.
function useComputedStyleText<T extends HTMLElement>(
  read: (cs: CSSStyleDeclaration) => string
): [RefObject<T | null>, string] {
  const ref = useRef<T>(null)
  const [value, setValue] = useState('')
  useEffect(() => {
    if (ref.current) setValue(read(getComputedStyle(ref.current)))
  }, [read])
  return [ref, value]
}

function Swatch({ name, color }: { name: string; color: string }) {
  const [ref, hex] = useComputedStyleText<HTMLDivElement>((cs) => rgbToHex(cs.backgroundColor))
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

function TypeEntry({ name, t }: { name: string; t: RampStyle }) {
  const [ref, meta] = useComputedStyleText<HTMLSpanElement>(
    (cs) => `${parseFloat(cs.fontSize)}px · ${cs.fontWeight}`
  )
  return (
    <div className="ds-type-entry">
      <div className="ds-type-entry-label">
        {name}
        <span className="ds-type-entry-meta">{meta}</span>
      </div>
      <div className="ds-type-entry-samples">
        <span ref={ref} className={t.standard}>{name}</span>
        <span className={t.emphasized}>{name}</span>
      </div>
    </div>
  )
}

const TYPE_COLUMNS: Array<{ label: string; keys: Array<keyof typeof text> }> = [
  { label: 'Primary', keys: ['largeTitle', 'title1', 'title2', 'title3'] },
  { label: 'Secondary', keys: ['headline', 'body', 'callout', 'control'] },
  { label: 'Tertiary', keys: ['caption', 'footnote'] }
]

function TypeColumn({ label, keys }: { label: string; keys: Array<keyof typeof text> }) {
  return (
    <div className="ds-type-col">
      <div className="ds-type-col-header">{label}</div>
      {keys.map((key) => (
        <TypeEntry key={key} name={humanize(key)} t={text[key]} />
      ))}
    </div>
  )
}

const CHIP_SHAPES: Array<{ label: string; extra?: string; content: (name: string) => ReactNode }> = [
  { label: 'Pill', content: (n) => n },
  { label: 'Select', content: () => <Icon name="circle-dashed" size={13} /> },
  { label: 'Checkbox', extra: chipCheckbox, content: () => <Icon name="check" size={12} strokeWidth={3} /> }
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
  const chipColors = Object.keys(chipColor) as Array<keyof typeof chipColor>
  const iconNames = Object.keys(icons) as Array<keyof typeof icons>

  return (
    <div className="ds-wrap">
      <header>
        <div className="ds-head">Pommora Design System</div>
      </header>

      <section className="ds-section">
        <h2>Color · Solid spectrum</h2>
        <div className="ds-swatches">
          {solids.map(([n, c]) => (
            <Swatch key={n} name={humanize(n)} color={c} />
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Typography · Inter</h2>
        <div className="ds-type-grid">
          {TYPE_COLUMNS.map((col) => (
            <TypeColumn key={col.label} label={col.label} keys={col.keys} />
          ))}
        </div>
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
                  className={[chip, chipColor[k], shape.extra].filter(Boolean).join(' ')}
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
        <h2>Icons · Lucide ({iconNames.length})</h2>
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
        <GlassStage />
        <div className="ds-mat-note">
          <b>Drag the glass anywhere</b> on the page — it starts over the middle surface and snaps
          back on reload.
        </div>
      </section>

      <section className="ds-section">
        <h2>Components</h2>
        <div className="ds-pending">
          {PENDING.map((x) => (
            <span key={x}>{x}</span>
          ))}
        </div>
      </section>
    </div>
  )
}
