import { useEffect, useMemo, useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { MenuScrollFrame, MenuSurface } from '@renderer/design-system/components/menu'
import type { NavTarget } from '@shared/types'
import { NavList } from '../Navigation/NavList'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import * as s from '../Components/Detail/settingsPane.css'
import './navmenu.css'

// NavMenu — the toolbar Navigation dropdown (G-2). Same shared nav layer as NavPane (useNavData),
// a compact dropdown presentation: the SettingsDropdown beak-glass surface, fixed height + internal
// scroll at the SettingsPane footprint (MenuScrollFrame's default ceiling). Content is the stub —
// search + favorites + recents; the polished form is Figma's.
export function NavMenu({
  closing = false,
  notchInsetRight,
  onClose
}: {
  closing?: boolean
  notchInsetRight?: number
  onClose: () => void
}): React.JSX.Element {
  const { resolvedRecents, resolvedFavorites, search, go } = useNavData()
  const [query, setQuery] = useState('')
  const searchRef = useRef<HTMLInputElement>(null)
  useEffect(() => searchRef.current?.focus(), [])

  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  const goClose = (target: NavTarget): void => go(target, onClose)

  return (
    <div className={s.anchor}>
      <MenuSurface closing={closing} notchInsetRight={notchInsetRight}>
        <div className="navmenu-search">
          <Icon name="search" size={14} />
          <input ref={searchRef} value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search…" spellCheck={false} />
        </div>
        <MenuScrollFrame>
          {results ? (
            <NavList items={results.items} extras={results.extras} onSelect={goClose} empty="No matches" />
          ) : (
            <>
              {resolvedFavorites.length > 0 && <NavList items={resolvedFavorites} onSelect={goClose} />}
              <NavList items={resolvedRecents} onSelect={goClose} empty="No recent items" />
            </>
          )}
        </MenuScrollFrame>
      </MenuSurface>
    </div>
  )
}
