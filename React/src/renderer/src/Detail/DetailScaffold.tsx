import { Banner } from './Banner/Banner'
import type { BannerOwner } from './Scope'

/**
 * The shared detail surface (Swift: ViewSurface): a full-bleed banner (or, banner-less, a title
 * header) above the body content. `owner` null ⇒ no header, just the body. With `lockedHeader` the
 * header is pinned and the body scrolls beneath it (content-views: the table scrolls, the banner
 * stays) — otherwise the whole surface scrolls (Swift's parking-header views). The body content is
 * the view's own.
 */
export function DetailScaffold({
  owner,
  children,
  lockedHeader = false
}: {
  owner: BannerOwner | null
  children?: React.ReactNode
  lockedHeader?: boolean
}): React.JSX.Element {
  const header = owner ? <Banner owner={owner} /> : null

  if (lockedHeader) {
    return (
      <div className="detail-locked">
        <div className="detail-locked-head">{header}</div>
        <div className="detail-locked-body">{children}</div>
      </div>
    )
  }

  return (
    <div className={'detail-scroll' + (owner ? ' has-header' : '')}>
      {header}
      <div className="detail-body">{children}</div>
    </div>
  )
}
