import { useMemo, useState } from 'react'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import type { NavTarget } from '@shared/types'
import { useSession } from '../store'
import { assetUrl } from '../assetUrl'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import { NavGallery } from '../NavWindow/NavGallery'
import { AddBannerButton } from '../Detail/Banner/AddBannerButton'
import '../Detail/Banner/Banner.css'
import './navView.css'

/** NavView — the new-tab page AND the empty state (E-1/E-2): a full-window gallery + search under a
 *  banner. The search bar IS the inline title — it sits in the banner-title slot over the NavView's
 *  own cover when one is set (`.nexus/navview.json`), else the homepage's as the default, or a
 *  banner-less header when neither exists. Shares NavGallery with NavWindow, never a merged shell (E-3). */
export function NavView(): React.JSX.Element {
  // resolvedRecents arrives already pin-deduped (useNavData filters against the pin set).
  const { resolvedRecents, resolvedPins, search, go } = useNavData()
  const ownBanner = useSession((s) => s.tree?.navView.banner)
  const homeBanner = useSession((s) => s.tree?.homepage.banner)
  const banner = ownBanner ?? homeBanner
  const mutate = useSession((s) => s.mutate)
  const [query, setQuery] = useState('')
  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  const open = (target: NavTarget): void => go(target)
  const openNew = (target: NavTarget): void => go(target, undefined, { newTab: true })

  // Change always writes the NavView's OWN banner; Remove clears only that override (falling back to
  // the homepage default), so it's offered only while an override exists — never the homepage's.
  const changeBanner = async (): Promise<void> => {
    const dataUrl = await window.nexus.pickImage()
    if (dataUrl) await mutate({ op: 'setBanner', path: '', kind: 'navview', dataUrl })
  }
  const onBannerMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.bannerMenu({ noRemove: !ownBanner })
    if (action === 'change') await changeBanner()
    else if (action === 'remove')
      await mutate({ op: 'setBanner', path: '', kind: 'navview', dataUrl: null })
  }

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
        <div className="banner nav-view-banner" onContextMenu={(e) => void onBannerMenu(e)}>
          <img className="banner-img" src={assetUrl(banner)} alt="" />
          <div className="banner-title">{searchInput}</div>
        </div>
      ) : (
        <div className="nav-view-head">
          <AddBannerButton onClick={() => void changeBanner()} />
          {searchInput}
        </div>
      )}
      <div className="nav-view-scroll edge-fade">
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
