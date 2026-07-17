import { useEffect, useRef } from 'react'
import { Banner } from './Banner/Banner'
import { isSurfaceKind, type BannerOwner } from './Scope'
import { useSession } from '../store'
import { navKey } from '../Navigation/navRecents'
import { captureWarm, readWarm } from '../Tabs/warmCache'

/**
 * The shared detail surface (Swift: ViewSurface): a full-bleed banner (or, banner-less, a title
 * header) above the body, both scrolling together. `owner` null ⇒ no header, just the body. The body
 * content is the view's own.
 */
export function DetailScaffold({
  owner,
  children,
}: {
  owner: BannerOwner | null
  children?: React.ReactNode
}): React.JSX.Element {
  const ref = useRef<HTMLDivElement>(null)
  const activeTabId = useSession((s) => s.activeTabId)
  const selection = useSession((s) => s.selection)
  // A container's warmth is its scroll position only (I-14) — undo/folds are page-editor concerns.
  const warmKey = selection.kind !== 'none' && selection.kind !== 'page' ? navKey(selection) : null

  // The scaffold's div is REUSED across containers (no key), so warmth rides this effect: restore on
  // (tab, entity) change, capture on leave. Scroll is tracked continuously into `last` — by cleanup
  // time the div may already hold the NEXT container's content (clamped scroll), so a teardown read
  // would capture the wrong value.
  useEffect(() => {
    const el = ref.current
    if (!el || !warmKey) return
    const saved = readWarm(activeTabId, warmKey)?.scrollTop
    el.scrollTop = saved ?? 0
    let last = saved ?? 0
    const onScroll = (): void => {
      last = el.scrollTop
    }
    el.addEventListener('scroll', onScroll, { passive: true })
    return () => {
      el.removeEventListener('scroll', onScroll)
      captureWarm(activeTabId, warmKey, { scrollTop: last })
    }
  }, [activeTabId, warmKey])

  return (
    <div
      ref={ref}
      className={
        'detail-scroll' +
        (owner ? ' has-header' : '') +
        (owner && isSurfaceKind(owner.kind) ? ' is-surface' : '')
      }
    >
      {owner ? <Banner owner={owner} /> : null}
      <div className="detail-body">{children}</div>
    </div>
  )
}
