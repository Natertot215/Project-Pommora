import type { ReactNode } from 'react'
import { Menu, MenuItem, MenuHeading, MenuSeparator } from '@renderer/design-system/components/menu'
import { Icon } from '@renderer/design-system/symbols'

// A constrained panel so the flush rows read like a real menu (≈ the Figma 230px card).
function Panel({ children }: { children: ReactNode }): React.JSX.Element {
  return (
    <div style={{ width: 240, background: '#FFFFFF0A', border: '1px solid #FFFFFF14', borderRadius: 10 }}>{children}</div>
  )
}

// Icons render at 1em (the new Icon default) → they follow each row's text step:
// 12px in a Menu Item, 13px in a Menu Heading.
const dashed = <Icon name="square-dashed" size={16} />
const chevron = <Icon name="chevron-right" size={12} />

export function MenuLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Menu · Items</h2>
        <Panel>
          <Menu>
            <MenuItem leading={dashed}>Title</MenuItem>
            <MenuItem leading={dashed} subLabel="Sub-label">Title</MenuItem>
            <MenuItem leading={dashed} detail="Detail">Title</MenuItem>
            <MenuItem leading={dashed} trailing={chevron}>Title</MenuItem>
            <MenuItem leading={<>{chevron}{dashed}</>}>Title</MenuItem>
            <MenuItem>Title</MenuItem>
            <MenuItem leading={<>{chevron}{dashed}</>} subLabel="Sub-label" detail="Detail" trailing={chevron}>
              Title
            </MenuItem>
          </Menu>
        </Panel>
      </section>

      <section className="ds-section">
        <h2>Menu · Heading</h2>
        <Panel>
          <Menu>
            <MenuHeading leading={dashed}>Heading</MenuHeading>
            <MenuHeading leading={dashed} detail="Detail">Heading</MenuHeading>
            <MenuHeading>Heading</MenuHeading>
          </Menu>
        </Panel>
      </section>

      <section className="ds-section">
        <h2>Menu · States</h2>
        <Panel>
          <Menu>
            <MenuItem leading={dashed}>Neutral</MenuItem>
            <MenuItem leading={dashed}>Hover — point at me</MenuItem>
            <MenuItem leading={dashed} selected>
              Selected
            </MenuItem>
          </Menu>
        </Panel>
      </section>

      <section className="ds-section">
        <h2>Menu · Separator</h2>
        <Panel>
          <Menu>
            <MenuItem leading={dashed}>Above</MenuItem>
            <MenuSeparator />
            <MenuItem leading={dashed}>Below</MenuItem>
          </Menu>
        </Panel>
      </section>
    </div>
  )
}
