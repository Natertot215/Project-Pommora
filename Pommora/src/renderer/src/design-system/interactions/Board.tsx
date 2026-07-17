import { useState } from 'react'
import { DragGroup, SortableZone, useGroupedDragItem, type Row } from './drag'

const COLS = ['Todo', 'Doing', 'Done']
const mk = (labels: string[], p: string): Row[] =>
  labels.map((l, i) => ({ id: `${p}${i}-${l}`, label: l }))

export function BoardSurface(): React.JSX.Element {
  const [cols, setCols] = useState<Record<string, Row[]>>({
    Todo: mk(['Draft spec', 'Collect refs', 'Sketch flows'], 't'),
    Doing: mk(['Sidebar resize', 'Glass material'], 'd'),
    Done: mk(['Window chrome', 'Token sync'], 'n'),
  })

  const labelOf = (id: string): string =>
    Object.values(cols)
      .flat()
      .find((it) => it.id === id)?.label ?? ''

  // Single commit on drop: pull the card from its column, insert into `toZone` at `toIndex`
  // (index among the destination's cards with the active one removed). No mid-drag churn.
  const onCommit = (activeId: string, toZone: string, toIndex: number): void => {
    setCols((prev) => {
      const fromZone = COLS.find((c) => prev[c].some((it) => it.id === activeId))
      if (!fromZone) return prev
      const card = prev[fromZone].find((it) => it.id === activeId)
      if (!card) return prev
      const without = { ...prev, [fromZone]: prev[fromZone].filter((it) => it.id !== activeId) }
      const dest = without[toZone]
      const at = Math.max(0, Math.min(toIndex, dest.length))
      return { ...without, [toZone]: [...dest.slice(0, at), card, ...dest.slice(at)] }
    })
  }

  return (
    <DragGroup
      onCommit={onCommit}
      renderOverlay={(id) => <div className="sx-item ix-overlay">{labelOf(id)}</div>}
    >
      <div className="ix-board">
        {COLS.map((c) => (
          <div className="ix-col" key={c}>
            <div className="ix-col-head">
              {c}
              <span className="ix-col-count">{cols[c].length}</span>
            </div>
            <SortableZone
              group="board"
              id={c}
              items={cols[c].map((it) => it.id)}
              className="sx-column"
            >
              {cols[c].map((it) => (
                <Card key={it.id} id={it.id} label={it.label} />
              ))}
            </SortableZone>
          </div>
        ))}
      </div>
    </DragGroup>
  )
}

function Card({ id, label }: { id: string; label: string }): React.JSX.Element {
  const { setNodeRef, style, handle } = useGroupedDragItem(id)
  return (
    <li ref={setNodeRef} style={style} className="sx-item" {...handle}>
      <span>{label}</span>
    </li>
  )
}
