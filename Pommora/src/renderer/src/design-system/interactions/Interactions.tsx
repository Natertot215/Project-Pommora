import { useState, type CSSProperties } from 'react'
import { FeelProvider, FEEL_PRESETS, EASINGS, DEFAULT_FEEL, type Feel } from './feel'
import {
  ListSurface,
  GridSurface,
  TableSurface,
  TreeSurface,
  ConstraintsSurface,
  ScrollSurface,
} from './Surfaces'
import { BoardSurface } from './Board'
import './interactions.css'

const SECTIONS = [
  { id: 'list', title: 'List', hint: 'Vertical reorder', el: <ListSurface /> },
  { id: 'grid', title: 'Grid', hint: '2D reflow · 12 cells', el: <GridSurface /> },
  { id: 'table', title: 'Table', hint: 'Row reorder · 4 columns', el: <TableSurface /> },
  {
    id: 'tree',
    title: 'Tree',
    hint: 'Recursive · 3 levels · reorder per level',
    el: <TreeSurface />,
  },
  { id: 'board', title: 'Two lists · drag between', hint: 'Cross-list move', el: <BoardSurface /> },
  {
    id: 'constraints',
    title: 'Constraints',
    hint: 'Swap · axis · bounds · async-reject',
    el: <ConstraintsSurface />,
  },
  {
    id: 'scroll',
    title: 'Scrolling list',
    hint: 'Auto-scroll at edges · 20 rows',
    el: <ScrollSurface />,
  },
]

export function Interactions(): React.JSX.Element {
  const [feel, setFeel] = useState<Feel>(DEFAULT_FEEL)
  const [presetName, setPresetName] = useState('Smooth')
  const easingName = Object.keys(EASINGS).find((k) => EASINGS[k] === feel.easing) ?? 'Custom'
  const vars = { '--ix-dur': `${feel.duration}ms`, '--ix-ease': feel.easing } as CSSProperties

  return (
    <FeelProvider feel={feel}>
      <div className="ix-wrap" style={vars}>
        <header className="ix-header">
          <div>
            <div className="ix-title">Interaction Lab</div>
            <p className="ix-sub">
              The in-house engine — two primitives drive every surface. Deep nesting, a 2D grid, a
              multi-column table, cross-list dragging, and the constraint options. One tunable
              transition throughout.
            </p>
          </div>
          <div className="ix-feel">
            <div className="ix-feel-presets">
              {Object.keys(FEEL_PRESETS).map((n) => (
                <button
                  key={n}
                  type="button"
                  className={'ix-preset' + (presetName === n ? ' is-on' : '')}
                  onClick={() => {
                    setPresetName(n)
                    setFeel(FEEL_PRESETS[n])
                  }}
                >
                  {n}
                </button>
              ))}
            </div>
            <label className="ix-feel-row">
              <span>Duration</span>
              <input
                type="range"
                min={80}
                max={500}
                step={10}
                value={feel.duration}
                onChange={(e) => {
                  setPresetName('Custom')
                  setFeel((f) => ({ ...f, duration: +e.target.value }))
                }}
              />
              <span className="ix-feel-val">{feel.duration}ms</span>
            </label>
            <div className="ix-feel-presets">
              {Object.keys(EASINGS).map((n) => (
                <button
                  key={n}
                  type="button"
                  className={'ix-preset' + (easingName === n ? ' is-on' : '')}
                  onClick={() => {
                    setPresetName('Custom')
                    setFeel((f) => ({ ...f, easing: EASINGS[n] }))
                  }}
                >
                  {n}
                </button>
              ))}
            </div>
          </div>
        </header>

        <div className="ix-sections">
          {SECTIONS.map((s) => (
            <section className="ix-card" key={s.id}>
              <div className="ix-card-head">
                <span className="ix-card-title">{s.title}</span>
                <span className="ix-card-hint">{s.hint}</span>
              </div>
              <div className="ix-card-body">{s.el}</div>
            </section>
          ))}
        </div>
      </div>
    </FeelProvider>
  )
}
