import { useEffect, useRef, useState } from 'react'
import { vars, text, chip, chipColor, chipSquare, chipCheckbox } from '@renderer/design/tokens'

// --- Colors: swatch background comes from the live token var; the hex label is
//     read back from the rendered color so it can't drift from the token. ---
const SOLIDS: ReadonlyArray<readonly [string, string]> = [
  ['Red', vars.color.solid.red],
  ['Orange', vars.color.solid.orange],
  ['Yellow', vars.color.solid.yellow],
  ['Green', vars.color.solid.green],
  ['Light Blue', vars.color.solid.lightBlue],
  ['Cyan', vars.color.solid.cyan],
  ['Blue', vars.color.solid.blue],
  ['Purple', vars.color.solid.purple],
  ['Lavender', vars.color.solid.lavender],
  ['Grey', vars.color.solid.grey],
  ['Grey Default', vars.color.solid.greyDefault]
]

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

// --- Typography ---
const RAMP: ReadonlyArray<readonly [string, string, { standard: string; emphasized: string }]> = [
  ['Large Title', '26 / 32 · Regular · Bold', text.largeTitle],
  ['Title 1', '22 / 26 · Regular · Bold', text.title1],
  ['Title 2', '17 / 22 · Regular · Bold', text.title2],
  ['Title 3', '15 / 20 · Regular · Bold', text.title3],
  ['Headline', '13 / 16 · Medium · Semibold', text.headline],
  ['Body', '13 / 16 · Regular · Bold', text.body],
  ['Callout', '12 / 15 · Regular · Bold', text.callout],
  ['Control', '12 / 15 · Regular · Semibold', text.control],
  ['Caption', '11 / 14 · Regular · Semibold', text.caption],
  ['Footnote', '10 / 13 · Regular · Semibold', text.footnote]
]

// --- Chips ---
const CHIP_COLORS: ReadonlyArray<readonly [string, keyof typeof chipColor]> = [
  ['Blue', 'blue'],
  ['Green', 'green'],
  ['Purple', 'purple'],
  ['Lavender', 'lavender'],
  ['Cyan', 'cyan'],
  ['Light Blue', 'lightBlue'],
  ['Orange', 'orange'],
  ['Yellow', 'yellow'],
  ['Grey', 'grey'],
  ['Default', 'default']
]

export function DesignSystem() {
  return (
    <div className="ds-wrap">
      <header>
        <div className="ds-head">Pommora — Design System</div>
        <div className="ds-sub">
          Live from the vanilla-extract tokens at <code>@renderer/design/tokens</code>. Colors ·
          Typography · Chips.
        </div>
      </header>

      <section className="ds-section">
        <h2>Color · Solid spectrum</h2>
        <div className="ds-swatches">
          {SOLIDS.map(([n, c]) => (
            <Swatch key={n} name={n} color={c} />
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Typography · Inter</h2>
        {RAMP.map(([n, meta, t]) => (
          <div className="ds-type-row" key={n}>
            <div className="ds-type-label">
              {n}
              <span className="ds-type-meta">{meta}</span>
            </div>
            <div className="ds-type-samples">
              <span className={t.standard}>{n}</span>
              <span className={t.emphasized}>{n}</span>
            </div>
          </div>
        ))}
      </section>

      <section className="ds-section">
        <h2>Chips · fill 60 · stroke 40 (2px, checkbox 1.5px) · text label-primary + 10%</h2>
        <div className="ds-chip-grid">
          <div className="ds-chip-row">
            <div className="ds-chip-rowlabel">Pill</div>
            {CHIP_COLORS.map(([n, k]) => (
              <span key={k} className={`${chip} ${chipColor[k]}`}>
                {n}
              </span>
            ))}
          </div>
          <div className="ds-chip-row">
            <div className="ds-chip-rowlabel">Select</div>
            {CHIP_COLORS.map(([n, k]) => (
              <span key={k} className={`${chip} ${chipColor[k]} ${chipSquare}`}>
                {n}
              </span>
            ))}
          </div>
          <div className="ds-chip-row">
            <div className="ds-chip-rowlabel">Checkbox</div>
            {CHIP_COLORS.map(([n, k]) => (
              <span key={k} className={`${chip} ${chipColor[k]} ${chipSquare} ${chipCheckbox}`}>
                ✓&nbsp;{n}
              </span>
            ))}
          </div>
        </div>
      </section>

      <section className="ds-section">
        <h2>In Figma · pending React components</h2>
        <div className="ds-pending">
          {[
            'Label',
            'Label · Segmented',
            'Button',
            'Button · Segmented',
            'Symbol',
            'Menu Item',
            'Menu Heading',
            'Separator'
          ].map((x) => (
            <span key={x}>{x}</span>
          ))}
        </div>
      </section>
    </div>
  )
}
