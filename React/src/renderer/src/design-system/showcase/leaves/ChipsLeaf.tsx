import { useState, type ReactNode } from 'react'
import { chipPill, chipLabel, chipContext, chipCapsule, chipBox, chipColor, chipLabelWrap } from '@renderer/design-system/tokens'
import { Icon } from '@renderer/design-system/symbols'
import { SortableZone, useDragItem, reorder } from '@renderer/design-system/interactions/drag'
import { cx } from '@renderer/design-system/cx'
import { humanize, useIsCompact } from './helpers'

type ChipColorName = keyof typeof chipColor
const CHIP_COLORS = Object.keys(chipColor) as ChipColorName[]
const pillClass = (color: ChipColorName): string => `${chipPill} ${chipColor[color]}`

function ChipCell({ id, color, label }: { id: string; color: ChipColorName; label: string }): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(id)
  return (
    <span ref={setNodeRef} style={style} className={pillClass(color)} {...handle} title={color}>
      <span className={chipLabelWrap}>{label}</span>
    </span>
  )
}

// The pill row reorders on desktop (the "list component reorders" demo); on a compact
// screen the pills are static so the page scrolls (drag sets touch-action:none).
function PillRow(): React.JSX.Element {
  const [items, setItems] = useState(() => CHIP_COLORS.map((c) => ({ id: c, name: humanize(c) })))
  const compact = useIsCompact()
  const cells = (
    <div className="ds-chip-row-items">
      {items.map((it) =>
        compact ? (
          <span key={it.id} className={pillClass(it.id)} title={it.id}><span className={chipLabelWrap}>{it.name}</span></span>
        ) : (
          <ChipCell key={it.id} id={it.id} color={it.id} label={it.name} />
        )
      )}
    </div>
  )
  if (compact) return cells
  return (
    <SortableZone
      items={items.map((i) => i.id)}
      layout="grid"
      getItemLabel={(id) => items.find((i) => i.id === id)?.name ?? id}
      onReorder={(a, o) => setItems((x) => reorder(x, a, o))}
    >
      {cells}
    </SortableZone>
  )
}

const STATIC_SHAPES: Array<{ label: string; shape: string; content: () => ReactNode }> = [
  { label: 'Label', shape: chipLabel, content: () => <span className={chipLabelWrap}>Label</span> },
  { label: 'Context', shape: chipContext, content: () => <span className={chipLabelWrap}>Context</span> },
  { label: 'Capsule', shape: chipCapsule, content: () => <Icon name="circle-dashed" size={13} /> },
  { label: 'Box', shape: chipBox, content: () => <Icon name="check" size={12} strokeWidth={3} /> }
]

// Components not yet built — they land as new leaves under the Components section.
const PENDING = ['Button', 'Label', 'Menu', 'Separator', 'Row']

export function ChipsLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Chips</h2>
        <div className="ds-chip-grid">
          <div className="ds-chip-row">
            <div className="ds-chip-rowlabel">Pill · drag to reorder</div>
            <PillRow />
          </div>
          {STATIC_SHAPES.map((shape) => (
            <div className="ds-chip-row" key={shape.label}>
              <div className="ds-chip-rowlabel">{shape.label}</div>
              {CHIP_COLORS.map((k) => (
                <span key={k} className={cx(shape.shape, chipColor[k])} title={k}>
                  {shape.content()}
                </span>
              ))}
            </div>
          ))}
        </div>
      </section>

      <section className="ds-section">
        <h2>Components · Coming soon</h2>
        <div className="ds-pending">
          {PENDING.map((x) => (
            <span key={x}>{x}</span>
          ))}
        </div>
      </section>
    </div>
  )
}
