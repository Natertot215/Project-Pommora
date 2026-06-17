import { Fragment, useEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import { vars, text, chip, chipColor, chipCheckbox, tint } from '@renderer/design-system/tokens'
import { Icon, icons } from '@renderer/design-system/symbols'
import { GlassStage } from './GlassStage'
import { applyAccent, readCssAccentColor } from '../accent'
import { ACCENT_COLORS, type AccentSetting } from '@shared/types'

// camelCase / kebab-case key -> "Title Case" label.
function humanize(key: string): string {
  return key
    .replace(/[-_]/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/([a-zA-Z])(\d)/g, '$1 $2')
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

// Read back the rendered color → "#RRGGBB", or "#RRGGBB · NN%" when it carries an alpha
// (the opacity tokens), so the gallery shows base + percent, never an opaque A## byte.
function formatColor(rgb: string): string {
  const m = rgb.match(/\d+(\.\d+)?/g)
  if (!m || m.length < 3) return rgb
  const ch = (n: string): string => Math.round(Number(n)).toString(16).padStart(2, '0')
  const hex = ('#' + m.slice(0, 3).map(ch).join('')).toUpperCase()
  const a = m.length >= 4 ? Number(m[3]) : 1
  return a < 1 ? `${hex} · ${Math.round(a * 100)}%` : hex
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
  const [ref, hex] = useComputedStyleText<HTMLDivElement>((cs) => formatColor(cs.backgroundColor))
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

function TypeEntry({ name, t, colorVar }: { name: string; t: RampStyle; colorVar: string }) {
  const [ref, meta] = useComputedStyleText<HTMLSpanElement>(
    (cs) => `${parseFloat(cs.fontSize)}px · ${cs.fontWeight}`
  )
  const color = `var(${colorVar})`
  return (
    <div className="ds-type-entry">
      <div className="ds-type-entry-label">
        {name}
        <span className="ds-type-entry-meta">{meta}</span>
      </div>
      <div className="ds-type-entry-samples" style={{ color }}>
        <span ref={ref} className={t.standard}>{name}</span>
        <span className={t.emphasized}>{name}</span>
      </div>
    </div>
  )
}

const ALL_TYPE_KEYS: Array<keyof typeof text> = [
  'largeTitle', 'title1', 'title2', 'title3',
  'headline', 'body', 'callout', 'control',
  'caption', 'footnote'
]

const TYPE_COLUMNS: Array<{ label: string; colorVar: string }> = [
  { label: 'Primary', colorVar: '--label-primary' },
  { label: 'Secondary', colorVar: '--label-secondary' },
  { label: 'Tertiary', colorVar: '--label-tertiary' }
]

function TypeColumn({ label, colorVar }: { label: string; colorVar: string }) {
  return (
    <div className="ds-type-col">
      <div className="ds-type-col-header">{label}</div>
      {ALL_TYPE_KEYS.map((key) => (
        <TypeEntry key={key} name={humanize(key)} t={text[key]} colorVar={colorVar} />
      ))}
    </div>
  )
}

const ACCENT_OPTIONS: AccentSetting[] = [...ACCENT_COLORS, 'system']

// Live accent picker: sets --accent on :root (fill/text derive). The samples
// read the CSS vars, so they recolor in place. Resets to the bridge default
// (lavender) on reload — the swap is ephemeral, like the glass demo.
function AccentDemo() {
  const [active, setActive] = useState<AccentSetting>('lavender')
  const [systemColor] = useState(() => readCssAccentColor())
  const pick = (a: AccentSetting): void => {
    setActive(a)
    applyAccent(a, a === 'system' ? systemColor : null)
  }
  return (
    <div className="ds-accent">
      <div className="ds-accent-swatches">
        {ACCENT_OPTIONS.map((a) => (
          <button
            key={a}
            type="button"
            className={
              'ds-accent-chip' +
              (a === active ? ' is-active' : '') +
              (a === 'system' ? ' is-system' : '')
            }
            style={{ background: a === 'system' ? systemColor ?? vars.color.solid.grey : vars.color.solid[a] }}
            onClick={() => pick(a)}
            title={a}
            aria-label={a}
          />
        ))}
      </div>
      <div className="ds-accent-samples">
        <span className="ds-accent-btn">Accent button</span>
        <span className={chip} style={tint('var(--accent)')}>Accent</span>
        <span className="ds-accent-link">Accent text</span>
      </div>
    </div>
  )
}

// Static color-token groups → labeled swatch grids. Accent is excluded; it has
// its own live picker section.
const COLOR_GROUPS: Array<[string, Record<string, string>]> = [
  ['Solid spectrum', vars.color.solid],
  ['Background', vars.color.background],
  ['Surface', vars.color.surface],
  ['Fills', vars.color.fill],
  ['States', vars.color.state],
  ['Separators', vars.color.separator]
]

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
  const chipColors = Object.keys(chipColor) as Array<keyof typeof chipColor>
  const iconNames = Object.keys(icons) as Array<keyof typeof icons>

  return (
    <div className="ds-wrap">
      <header>
        <div className="ds-head">Pommora Design System</div>
      </header>

      <section className="ds-section">
        {COLOR_GROUPS.map(([label, group], i) => (
          <Fragment key={label}>
            <h2 style={i > 0 ? { marginTop: 28 } : undefined}>{`Color · ${label}`}</h2>
            <div className="ds-swatches">
              {Object.entries(group).map(([n, c]) => (
                <Swatch key={n} name={humanize(n)} color={c} />
              ))}
            </div>
          </Fragment>
        ))}
      </section>

      <section className="ds-section">
        <h2>Color · Accent</h2>
        <AccentDemo />
      </section>

      <section className="ds-section">
        <h2>Typography · Inter</h2>
        <div className="ds-type-grid">
          {TYPE_COLUMNS.map((col) => (
            <TypeColumn key={col.label} label={col.label} colorVar={col.colorVar} />
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Chips</h2>
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
