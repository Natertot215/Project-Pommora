import { useState, type CSSProperties } from 'react'
import { vars, chipPill, tint, tintAt, TINT_STEPS } from '@renderer/design-system/tokens'
import { SortableZone, useDragItem, reorder } from '@renderer/design-system/interactions/drag'
import { applyAccent, readCssAccentColor } from '../../accent'
import { ACCENT_COLORS, type AccentSetting } from '@shared/types'
import { humanize, formatColor, useComputedStyleText, useIsCompact } from './helpers'

// Primitives first (the base palette), then the derived token groups. Accent is
// excluded from the static groups — it has its own live picker below.
const PRIMITIVE_GROUP: [string, Record<string, string>] = ['Primitives', vars.color.system]
const COLOR_GROUPS: Array<[string, Record<string, string>]> = [
  ['Solid spectrum', vars.color.solid],
  ['Label', vars.color.label],
  ['Background', vars.color.background],
  ['Surface', vars.color.surface],
  ['Fills', vars.color.fill],
  ['States', vars.color.state],
  ['Separators', vars.color.separator]
]

type SwatchItem = { id: string; name: string; color: string }

// Presentational swatch. Reads its rendered color back off the inner chip (so the
// shown hex can't drift from the token); optional drag bindings sit on the outer
// node — distinct from the read-back ref, so they never collide.
function SwatchView({ name, color, dragRef, style, handle }: {
  name: string
  color: string
  dragRef?: (el: HTMLDivElement | null) => void
  style?: CSSProperties
  handle?: Record<string, unknown>
}): React.JSX.Element {
  const [ref, hex] = useComputedStyleText<HTMLDivElement>((cs) => formatColor(cs.backgroundColor))
  return (
    <div ref={dragRef} style={style} className="ds-swatch" {...handle}>
      <div ref={ref} className="ds-swatch-chip" style={{ background: color }} />
      <div className="ds-swatch-meta">
        <div className="ds-swatch-name">{name}</div>
        <div className="ds-swatch-hex">{hex}</div>
      </div>
    </div>
  )
}

/** The ghost state is an OPACITY, not a color (`opacity: var(--state-ghost)` — the drag dim):
 *  a white chip rendered AT that opacity, value shown as the percent it resolves to. */
function GhostSwatch(): React.JSX.Element {
  return (
    <div className="ds-swatch">
      <div className="ds-swatch-chip" style={{ background: vars.color.background.window }}>
        <div style={{ width: '100%', height: '100%', background: vars.color.system.white, opacity: TINT_STEPS.primary / 100 }} />
      </div>
      <div className="ds-swatch-meta">
        <div className="ds-swatch-name">Ghost</div>
        <div className="ds-swatch-hex">{`Opacity · ${TINT_STEPS.primary}%`}</div>
      </div>
    </div>
  )
}

function SwatchDraggable({ id, name, color }: SwatchItem): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(id)
  return <SwatchView name={name} color={color} dragRef={setNodeRef} style={style} handle={handle} />
}

// A color group. On desktop it's a reorderable gallery (grid reflow); on a compact
// screen the swatches are static so the page scrolls (a draggable item sets
// touch-action:none, which would trap touch scrolling on the tall grid).
function SwatchGroup({ label, group, append }: { label: string; group: Record<string, string>; append?: React.ReactNode }): React.JSX.Element {
  const [items, setItems] = useState<SwatchItem[]>(() =>
    Object.entries(group).map(([n, c]) => ({ id: n, name: humanize(n), color: c }))
  )
  const compact = useIsCompact()
  const cells = (
    <div className={'ds-swatches' + (compact ? '' : ' ds-swatches-drag')}>
      {items.map((it, i) => (
        <span key={it.id} style={{ display: 'contents' }}>
          {i === items.length - 1 ? append : null}
          {compact ? (
            <SwatchView name={it.name} color={it.color} />
          ) : (
            <SwatchDraggable id={it.id} name={it.name} color={it.color} />
          )}
        </span>
      ))}
    </div>
  )
  return (
    <section className="ds-section">
      <h2>{`Color · ${label}`}</h2>
      {compact ? (
        cells
      ) : (
        <SortableZone
          items={items.map((i) => i.id)}
          layout="grid"
          getItemLabel={(id) => items.find((i) => i.id === id)?.name ?? id}
          onReorder={(a, o) => setItems((x) => reorder(x, a, o))}
        >
          {cells}
        </SortableZone>
      )}
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
          <span className={chipPill} style={tint('var(--accent)')}>Accent</span>
          <span className="ds-accent-link">Accent text</span>
        </div>
      </div>
    </section>
  )
}

// The tint scale (opacity steps) applied across the spectrum — one row per color,
// five steps primary → solid. Static reference (each is the color over the page).
const TINT_ORDER = ['primary', 'secondary', 'tertiary', 'quaternary', 'solid'] as const

function TintRow({ name, color }: { name: string; color: string }): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(name)
  return (
    <div ref={setNodeRef} style={style} className="ds-tint-row" {...handle}>
      <span className="ds-tint-rowlabel">{humanize(name)}</span>
      {TINT_ORDER.map((k) => (
        <span
          key={k}
          className="ds-tint-swatch"
          style={{ background: tintAt(color, TINT_STEPS[k]) }}
          title={`${name} · ${k} ${TINT_STEPS[k]}%`}
        />
      ))}
    </div>
  )
}

function TintScale(): React.JSX.Element {
  const [colors, setColors] = useState(() => Object.entries(vars.color.solid))
  const compact = useIsCompact()
  const rows = compact ? (
    <>
      {colors.map(([name, color]) => (
        <div className="ds-tint-row" key={name}>
          <span className="ds-tint-rowlabel">{humanize(name)}</span>
          {TINT_ORDER.map((k) => (
            <span key={k} className="ds-tint-swatch" style={{ background: tintAt(color, TINT_STEPS[k]) }} title={`${name} · ${k} ${TINT_STEPS[k]}%`} />
          ))}
        </div>
      ))}
    </>
  ) : (
    <SortableZone
      items={colors.map(([n]) => n)}
      layout="grid"
      getItemLabel={(id) => humanize(id)}
      onReorder={(a, o) => setColors((x) => reorder(x.map(([n, c]) => ({ id: n, c })), a, o).map(({ id, c }) => [id, c] as (typeof x)[number]))}
    >
      <>
        {colors.map(([name, color]) => (
          <TintRow key={name} name={name} color={color} />
        ))}
      </>
    </SortableZone>
  )
  return (
    <section className="ds-section">
      <h2>Color · Tints</h2>
      <div className="ds-tints">
        <div className="ds-tint-row ds-tint-head">
          <span className="ds-tint-rowlabel" />
          {TINT_ORDER.map((k) => (
            <span key={k} className="ds-tint-steplabel">
              {k} · {TINT_STEPS[k]}%
            </span>
          ))}
        </div>
        {rows}
      </div>
    </section>
  )
}

export function ColorsLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <SwatchGroup label={PRIMITIVE_GROUP[0]} group={PRIMITIVE_GROUP[1]} />
      {COLOR_GROUPS.map(([label, group]) => (
        <SwatchGroup key={label} label={label} group={group} append={label === 'States' ? <GhostSwatch /> : undefined} />
      ))}
      <TintScale />
      <AccentDemo />
    </div>
  )
}
