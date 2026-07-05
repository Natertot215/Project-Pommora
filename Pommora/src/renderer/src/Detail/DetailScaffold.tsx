import { Banner } from './Banner/Banner'
import type { BannerOwner } from './Scope'

/**
 * The shared detail surface (Swift: ViewSurface): a full-bleed banner (or, banner-less, a title
 * header) above the body, both scrolling together. `owner` null ⇒ no header, just the body. The body
 * content is the view's own.
 */
export function DetailScaffold({
  owner,
  children
}: {
  owner: BannerOwner | null
  children?: React.ReactNode
}): React.JSX.Element {
  return (
    <div className={'detail-scroll' + (owner ? ' has-header' : '')}>
      {owner ? <Banner owner={owner} /> : null}
      <div className="detail-body">{children}</div>
    </div>
  )
}
