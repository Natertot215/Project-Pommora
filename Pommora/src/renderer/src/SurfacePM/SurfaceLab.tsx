import { useCallback, useMemo, useState } from 'react'
import type { SurfaceLayout } from './core/model'
import { tileIds } from './core/model'
import type { Rect } from './core/rects'
import { insertBand, splitAtTile } from './core/ops'
import { SurfaceView } from './SurfaceView'

// SurfacePM's lab — dummy numbered tiles over the live engine, for driving the
// tessellation by hand: handle-drag to move (edge quadrants + band seams preview
// the real result), block edges/corners to resize, Esc aborts anything.

function demoLayout(): SurfaceLayout {
  let l: SurfaceLayout = { bands: [] }
  l = insertBand(l, 0, 't1', 260)
  l = splitAtTile(l, 't1', 'e', 't2')
  l = splitAtTile(l, 't2', 'e', 't3', 0.4)
  l = splitAtTile(l, 't2', 's', 't4', 0.45)
  l = splitAtTile(l, 't1', 's', 't5', 0.3)
  l = insertBand(l, 1, 't6', 200)
  l = splitAtTile(l, 't6', 'e', 't7', 0.65)
  l = splitAtTile(l, 't7', 's', 't8')
  l = splitAtTile(l, 't8', 'e', 't9')
  return l
}

function stressLayout(): SurfaceLayout {
  let l: SurfaceLayout = { bands: [] }
  let n = 0
  for (let band = 0; band < 10; band++) {
    const first = `s${n++}`
    l = insertBand(l, band, first, 180)
    const row = [first]
    for (let k = 0; k < 3; k++) {
      const id = `s${n++}`
      l = splitAtTile(l, row[k] as string, 'e', id)
      row.push(id)
    }
    l = splitAtTile(l, row[0] as string, 's', `s${n++}`)
    l = splitAtTile(l, row[2] as string, 's', `s${n++}`)
  }
  return l
}

export function SurfaceLab(): React.JSX.Element {
  const [layout, setLayout] = useState<SurfaceLayout>(demoLayout)
  const nextId = useMemo(() => {
    const ids = tileIds(layout)
    let n = ids.length + 1
    while (ids.includes(`t${n}`)) n++
    return `t${n}`
  }, [layout])

  const addTile = (): void => {
    const first = tileIds(layout)[0]
    setLayout(
      first ? splitAtTile(layout, first, 'w', nextId, 0.35) : insertBand(layout, 0, nextId, 200)
    )
  }
  const addBand = (): void => setLayout(insertBand(layout, layout.bands.length, nextId, 180))

  const renderTile = useCallback(
    (id: string, _rect: Rect) => (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'grid',
          placeItems: 'center',
          fontSize: 15,
          fontWeight: 600,
          color: 'var(--label-secondary)',
          userSelect: 'none'
        }}
      >
        {id.replace(/^[ts]/, '')}
      </div>
    ),
    []
  )

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div style={{ display: 'flex', gap: 8 }}>
        <button type="button" onClick={addTile}>
          Add Tile
        </button>
        <button type="button" onClick={addBand}>
          Add Band
        </button>
        <button type="button" onClick={() => setLayout(stressLayout())}>
          Stress (60)
        </button>
        <button type="button" onClick={() => setLayout(demoLayout())}>
          Reset
        </button>
      </div>
      <SurfaceView layout={layout} onLayoutChange={setLayout} renderTile={renderTile} />
    </div>
  )
}
