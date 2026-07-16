import { useMemo, useState } from 'react'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import type { NavTarget } from '@shared/types'
import { useSession } from '../store'
import { assetUrl } from '../assetUrl'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import { NavGallery } from '../NavWindow/NavGallery'
import '../Detail/Banner/Banner.css'
import './navView.css'

/** NavView — the new-tab page AND the empty state (E-1/E-2): a full-window gallery + search under the
 *  Homepage banner. The search bar IS the inline title — it sits in the banner-title slot over the
 *  homepage's cover (shared by default; its own once a NavView cover ships), or a banner-less header
 *  when no cover is set. Shares NavGallery with NavWindow, never a merged shell (E-3). */
export function NavView(): React.JSX.Element {
  // resolvedRecents arrives already pin-deduped (useNavData filters against the pin set).
  const { resolvedRecents, resolvedPins, search, go } = useNavData()
  const banner = useSession((s) => s.tree?.homepage.banner)
  const [query, setQuery] = useState('')
  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  const open = (target: NavTarget): void => go(target)
  const openNew = (target: NavTarget): void => go(target, undefined, { newTab: true })

  const searchInput = (
    <input
      className={cx('nav-view-search', text.body.standard)}
      value={query}
      onChange={(e) => setQuery(e.target.value)}
      placeholder="Search…"
      spellCheck={false}
    />
  )

  return (
    <div className="nav-view">
      {banner ? (
        // Starts with the Homepage's banner; the search is the inline title over it.
        <div className="banner nav-view-banner">
          <img className="banner-img" src={assetUrl(banner)} alt="" />
          <div className="banner-title">{searchInput}</div>
        </div>
      ) : (
        <div className="nav-view-head">{searchInput}</div>
      )}
      <div className="nav-view-scroll scroll-edge-fade">
        {/* NavView is a gallery, so search stays in gallery cards (never the list) — filtered items only,
            no pins section; unresolvable agenda matches (extras) can't be cards and drop out. */}
        <NavGallery
          pins={results ? [] : resolvedPins}
          items={results ? results.items : resolvedRecents}
          frozenLayout={!!results}
          onSelect={open}
          onOpenNewTab={openNew}
        />
      </div>
    </div>
  )
}
