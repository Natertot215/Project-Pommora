import { useState } from 'react'
import { vars, chip, tint } from '@renderer/design-system/tokens'
import { SortableZone, useDragItem, reorder } from '@renderer/design-system/interactions/drag'
import { applyAccent, readCssAccentColor } from '../../accent'
import { ACCENT_COLORS, type AccentSetting } from '@shared/types'
import { humanize, formatColor, useComputedStyleText } from './helpers'

// Static color-token groups → labeled swatch grids. Accent is excluded; it has its
// own live picker below.
const COLOR_GROUPS: Array<[string, Record<string, string>]> = [
  ['Solid spectrum', vars.color.solid],
  ['Background', vars.color.background],
  ['Surface', vars.color.surface],
  ['Fills', vars.color.fill],
  ['States', vars.color.state],
  ['Separators', vars.color.separator]
]

type SwatchItem = { id: string; name: string; color: string }

function SwatchCell({ id, name, color }: SwatchItem): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(id)
  const [ref, hex] = useComputedStyleText<HTMLDivElement>((cs) => formatColor(cs.backgroundColor))
  return (
    <div ref={setNodeRef} style={style} className="ds-swatch" {...handle}>
      <div ref={ref} className="ds-swatch-chip" style={{ background: color }} />
      <div className="ds-swatch-meta">
        <div className="ds-swatch-name">{name}</div>
        <div className="ds-swatch-hex">{hex}</div>
      </div>
    </div>
  )
}

// A color group as a reorderable gallery (grid reflow) — the "color gallery uses
// gallery DnD" demo. Order is ephemeral showcase play; it resets on reload.
function SwatchGroup({ label, group }: { label: string; group: Record<string, string> }): React.JSX.Element {
  const [items, setItems] = useState<SwatchItem[]>(() =>
    Object.entries(group).map(([n, c]) => ({ id: n, name: humanize(n), color: c }))
  )
  return (
    <section className="ds-section">
      <h2>{`Color · ${label}`}</h2>
      <SortableZone
        items={items.map((i) => i.id)}
        layout="grid"
        getItemLabel={(id) => items.find((i) => i.id === id)?.name ?? id}
        onReorder={(a, o) => setItems((x) => reorder(x, a, o))}
      >
        <div className="ds-swatches ds-swatches-drag">
          {items.map((it) => (
            <SwatchCell key={it.id} id={it.id} name={it.name} color={it.color} />
          ))}
        </div>
      </SortableZone>
    </section>
  )
}

const ACCENT_OPTIONS: AccentSetting[] = [...ACCENT_COLORS, 'system']

// Live accent picker: sets --accent on :root (fill / text derive). Samples read the
// CSS vars, so they recolor in place. Resets to the bridge default on reload.
function AccentDemo(): React.JSX.Element {
  const [active, setActive] = useState<AccentSetting>('lavender')
  const [systemColor] = useState(() => readCssAccentColor())
  const pick = (a: AccentSetting): void => {
    setActive(a)
    applyAccent(a, a === 'system' ? systemColor : null)
  }
  return (
    <section className="ds-section">
      <h2>Color · Accent</h2>
      <div className="ds-accent">
        <div className="ds-accent-swatches">
          {ACCENT_OPTIONS.map((a) => (
            <button
              key={a}
              type="button"
              className={'ds-accent-chip' + (a === active ? ' is-active' : '') + (a === 'system' ? ' is-system' : '')}
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
    </section>
  )
}

export function ColorsLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      {COLOR_GROUPS.map(([label, group]) => (
        <SwatchGroup key={label} label={label} group={group} />
      ))}
      <AccentDemo />
    </div>
  )
}
