import { useEffect } from 'react'
import type { SelectionState } from '@shared/types'
import { text } from '@renderer/design-system/tokens'
import { useSession } from '../../store'
import { subfieldCrumbs, pageContainerId } from './crumbs'
import { SubfieldBreadcrumb } from './SubfieldBreadcrumb'
import { DEFAULT_ITEMS, SubfieldItem, type SubfieldScope, isSubfieldItemId } from './subfieldItems'
import './subfield.css'

const basename = (path: string): string => (path.split('/').pop() ?? path).replace(/\.md$/, '')

/**
 * The Subfield (footer): breadcrumb on the left, per-view items on the right. Unscoped it reads the
 * open view from the selection and records the last-visited page per container (for the dimmed
 * "forward" ghost crumb). A host may pass a `scope` (the floating preview) — then it describes the
 * scope's page and counts the scope's own body instead. App-level collapse is driven from the host.
 */
export function Subfield({ scope }: { scope?: SubfieldScope }): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const tree = useSession((s) => s.tree)
  const trail = useSession((s) => s.trail)
  const select = useSession((s) => s.select)
  const recordTrail = useSession((s) => s.recordTrail)
  const pageDetail = useSession((s) => s.pageDetail)

  // While viewing a page, remember it as its container's forward-trail (for the ghost crumb).
  // A scoped (preview) Subfield is tab-neutral — it must not write the trail.
  useEffect(() => {
    if (scope || selection.kind !== 'page' || !tree) return
    const containerId = pageContainerId(tree, selection.id)
    if (!containerId) return
    recordTrail(containerId, {
      id: selection.id,
      path: selection.path,
      title: pageDetail?.title ?? basename(selection.path),
    })
  }, [scope, selection, tree, pageDetail, recordTrail])

  const order = useSession((s) => s.subfieldOrder)
  const crumbSelection: SelectionState = scope
    ? { kind: 'page', id: scope.target.id, path: scope.target.path }
    : selection
  const rawCrumbs = subfieldCrumbs(tree, crumbSelection, trail, (t) => void select(t))
  // The preview is tab-neutral — its crumbs describe location but don't navigate the main pane.
  const crumbs = scope ? rawCrumbs.map((c) => ({ ...c, onClick: undefined })) : rawCrumbs
  // Items describe the same view as the crumbs — the scoped page under a preview, else the selection.
  const kind = crumbSelection.kind
  // Persisted order wins (filtered to known ids); fall back to the registry default per view kind.
  const items = (order[kind] ?? DEFAULT_ITEMS[kind] ?? []).filter(isSubfieldItemId)

  return (
    <div className={`subfield ${text.subline.emphasized}`}>
      <SubfieldBreadcrumb crumbs={crumbs} />
      <div className="subfield-items">
        {items.map((id) => (
          <SubfieldItem key={id} id={id} scope={scope} />
        ))}
      </div>
    </div>
  )
}
