import { Banner } from './Banner/Banner'
import type { BannerOwner } from './Scope'

/**
 * The shared detail surface (Swift: ViewSurface): a full-bleed banner behind the glass above a
 * padded body, separated by the banner's divider. `owner` null ⇒ no banner, just the body.
 * Every banner-bearing view composes through this; the body content is the view's own.
 */
export function DetailScaffold({
  owner,
  children
}: {
  owner: BannerOwner | null
  children?: React.ReactNode
}): React.JSX.Element {
  const hasBanner = !!owner?.banner
  return (
    <div className={hasBanner ? 'detail-scroll has-banner' : 'detail-scroll'}>
      {owner && hasBanner && <Banner owner={owner} />}
      <div className="detail-body">
        {owner && !hasBanner && <Banner owner={owner} />}
        {children}
      </div>
    </div>
  )
}
