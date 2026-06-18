import { useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useHashRoute, setHashRoute } from './useHashRoute'
import { LEAVES, leafById } from './leaves/registry'
import { ShowcaseSidebar } from './ShowcaseSidebar'
import { ShowcaseMobileNav } from './ShowcaseMobileNav'

// The showcase shell: glass sidebar + content pane, mirroring the app's
// shell → surface-glass → content layout. Hash routing selects the active leaf;
// the registry is the single source for both nav and content.
export function Showcase(): React.JSX.Element {
  const activeId = useHashRoute(LEAVES[0].id)
  const [collapsed, setCollapsed] = useState(false)
  const leaf = leafById(activeId)
  const select = (id: string): void => setHashRoute(id)

  return (
    <div className={'sc-shell' + (collapsed ? ' sidebar-hidden' : '')}>
      <ShowcaseSidebar activeId={leaf.id} onSelect={select} onCollapse={() => setCollapsed(true)} />
      <button type="button" className="sc-expand" title="Show sidebar" aria-label="Show sidebar" onClick={() => setCollapsed(false)}>
        <Icon name="log-out" size={16} />
      </button>
      <ShowcaseMobileNav activeId={leaf.id} onSelect={select} />
      <main className="sc-content">{leaf.render()}</main>
    </div>
  )
}
