import { useEffect } from 'react'
import { text } from '@renderer/design-system/tokens'
import { useSession } from '../../store'
import { subfieldCrumbs, pageContainerId } from './crumbs'
import { SubfieldBreadcrumb } from './SubfieldBreadcrumb'
import { DEFAULT_ITEMS, SubfieldItem, isSubfieldItemId } from './subfieldItems'
import './subfield.css'

const basename = (path: string): string => (path.split('/').pop() ?? path).replace(/\.md$/, '')

/**
 * The Subfield (footer): breadcrumb on the left, per-view items on the right. Reads the open view
 * from the selection; records the last-visited page per container so a container's breadcrumb can
 * show the dimmed "forward" ghost crumb. App-level collapse is driven from DetailPane.
 */
export function Subfield(): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const tree = useSession((s) => s.tree)
  const trail = useSession((s) => s.trail)
  const select = useSession((s) => s.select)
  const recordTrail = useSession((s) => s.recordTrail)
  const pageDetail = useSession((s) => s.pageDetail)

  // While viewing a page, remember it as its container's forward-trail (for the ghost crumb).
  useEffect(() => {
    if (selection.kind !== 'page' || !tree) return
    const containerId = pageContainerId(tree, selection.id)
    if (!containerId) return
    recordTrail(containerId, {
      id: selection.id,
      path: selection.path,
      title: pageDetail?.title ?? basename(selection.path)
    })
  }, [selection, tree, pageDetail, recordTrail])

  const order = useSession((s) => s.subfieldOrder)
  const crumbs = subfieldCrumbs(tree, selection, trail, (t) => void select(t))
  // Persisted order wins (filtered to known ids); fall back to the registry default per view kind.
  const items = (order[selection.kind] ?? DEFAULT_ITEMS[selection.kind] ?? []).filter(isSubfieldItemId)

  return (
    <div className={`subfield ${text.subline.emphasized}`}>
      <SubfieldBreadcrumb crumbs={crumbs} />
      <div className="subfield-items">
        {items.map((id) => (
          <SubfieldItem key={id} id={id} />
        ))}
      </div>
    </div>
  )
}
