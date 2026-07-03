import { useState } from 'react'
import { ChipsLeaf } from './ChipsLeaf'
import { MenuLeaf } from './MenuLeaf'
import { CalendarPickerLeaf } from './CalendarPickerLeaf'
import { StubLeaf } from './StubLeaf'

/** ONE components page — a button row swaps which component's demo shows (Nathan's call:
 *  buttons over menus, not a sidebar leaf per component). Adding a component = one VIEWS row. */
const VIEWS = [
  { id: 'chips', label: 'Chips', render: () => <ChipsLeaf /> },
  { id: 'menu', label: 'Menu', render: () => <MenuLeaf /> },
  { id: 'calendar-picker', label: 'CalendarPicker', render: () => <CalendarPickerLeaf /> },
  { id: 'picker-menu', label: 'PickerMenu', render: () => <StubLeaf name="PickerMenu" /> },
  { id: 'overflow-scroll', label: 'OverflowScroll', render: () => <StubLeaf name="OverflowScroll" /> },
  { id: 'notched-pane', label: 'NotchedPane', render: () => <StubLeaf name="NotchedPane" /> }
] as const

type ViewId = (typeof VIEWS)[number]['id']

export function ComponentsLeaf(): React.JSX.Element {
  const [view, setView] = useState<ViewId>('chips')
  const active = VIEWS.find((v) => v.id === view) ?? VIEWS[0]
  return (
    <div className="ds-leaf">
      <div className="ds-switcher">
        {VIEWS.map((v) => (
          <button
            key={v.id}
            type="button"
            className={'ds-switcher-btn' + (v.id === view ? ' is-active' : '')}
            onClick={() => setView(v.id)}
          >
            {v.label}
          </button>
        ))}
      </div>
      {active.render()}
    </div>
  )
}
