import { useMemo, useState } from 'react'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import type { NavTarget } from '@shared/types'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import { NavList } from '../Navigation/NavList'
import { NavGallery } from '../NavWindow/NavGallery'
import './navView.css'

/** NavView — the new-tab page AND the empty state (E-1/E-2): the NavWindow gallery scaled full-window
 *  on the main background, the search bar sitting where a banner title would. Picking replaces the
 *  scratch newtab tab in place (openTab's replace branch). Shares NavGallery with NavWindow — two
 *  surfaces over one component, never a merged shell (E-3). */
export function NavView(): React.JSX.Element {
  // resolvedRecents arrives already pin-deduped (useNavData filters against the pin set).
  const { resolvedRecents, resolvedPins, search, go } = useNavData()
  const [query, setQuery] = useState('')
  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  const open = (target: NavTarget): void => go(target)
  const openNew = (target: NavTarget): void => go(target, undefined, { newTab: true })

  return (
    <div className="nav-view">
      <div className="nav-view-head">
        <input
          className={cx('nav-view-search', text.body.standard)}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search…"
          spellCheck={false}
          autoFocus
        />
      </div>
      <div className="nav-view-scroll scroll-edge-fade">
        {results ? (
          <NavList items={results.items} extras={results.extras} onSelect={open} onOpenNewTab={openNew} />
        ) : (
          <NavGallery pins={resolvedPins} items={resolvedRecents} onSelect={open} onOpenNewTab={openNew} />
        )}
      </div>
    </div>
  )
}
