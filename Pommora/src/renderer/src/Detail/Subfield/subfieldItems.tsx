import { Fragment, useMemo } from 'react'
import type { SelectionState } from '@shared/types'
import { subSetLabel } from '@shared/types'
import { DEFAULT_NEW_NAME } from '@shared/mutate'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { findCollection } from '../Scope'
import { computeStats } from './subfieldStats'

/** The catalog of Subfield items. v1: page document stats + the container add-menu. New ids slot in
 *  here, and the per-view default order below — the seam for future user-defined (scoped) items. */
export type SubfieldItemId = 'pageStats' | 'addMenu' | 'viewType'

const ALL_ITEM_IDS: SubfieldItemId[] = ['pageStats', 'addMenu', 'viewType']
/** Narrow a persisted (untrusted) id string to a known item id — drops stale/unknown entries. */
export function isSubfieldItemId(id: string): id is SubfieldItemId {
  return (ALL_ITEM_IDS as string[]).includes(id)
}

/** An optional per-mount scope. When a host (the floating preview) passes it, the footer describes
 *  THIS target and counts THIS body instead of the global selection/`liveBody`. The preview's body
 *  is its own local buffer — never the shared `liveBody` slot, which has a single owner (the active
 *  main editor); a second writer would evict the main pane's live count to its saved snapshot. */
export interface SubfieldScope {
  target: { id: string; path: string }
  body: string
}
export interface SubfieldItemProps {
  scope?: SubfieldScope
}

export const DEFAULT_ITEMS: Record<SelectionState['kind'], SubfieldItemId[]> = {
  none: ['viewType'],
  homepage: [],
  context: [],
  collection: ['addMenu'],
  set: ['addMenu'],
  page: ['pageStats'],
}

/** Lines · Words · Characters for the open page — live as you type. Scoped (the preview), it counts
 *  the scope's own body. Unscoped (the detail pane), the editing buffer wins over the loaded snapshot
 *  while it's for this same page; falls back to the loaded body before any edit. */
function PageStatsItem({ scope }: SubfieldItemProps): React.JSX.Element {
  const pageDetail = useSession((s) => s.pageDetail)
  const liveBody = useSession((s) => s.liveBody)
  const body = scope
    ? scope.body
    : liveBody && liveBody.path === pageDetail?.path
      ? liveBody.body
      : (pageDetail?.body ?? '')
  const stats = useMemo(() => computeStats(body), [body])
  const parts = [stats.lines, stats.words, stats.characters]
  return (
    <span className="subfield-stats" title="Lines · Words · Characters">
      {parts.map((n, i) => (
        <Fragment key={i}>
          {i > 0 && <span className="subfield-sep">·</span>}
          {n.toLocaleString()}
        </Fragment>
      ))}
    </span>
  )
}

/** "+" → native New Page / New <container> menu for the open Collection or Set. */
function AddMenuItem(): React.JSX.Element | null {
  const selection = useSession((s) => s.selection)
  const tree = useSession((s) => s.tree)
  if (selection.kind !== 'collection' && selection.kind !== 'set') return null
  const labels = tree?.labels
  const parentPath =
    selection.kind === 'set' ? selection.path : (findCollection(tree, selection.id)?.path ?? '')
  const containerLabel =
    selection.kind === 'collection'
      ? (labels?.pageSet.singular ?? 'Set')
      : labels
        ? subSetLabel(labels)
        : 'Sub-Set'
  const onAdd = (): void => {
    void useSession.getState().createFromMenu([
      { label: 'New Page', req: { op: 'createPage', parentPath, name: DEFAULT_NEW_NAME } },
      {
        label: `New ${containerLabel}`,
        req: { op: 'createContainer', parentPath, kind: 'set', name: DEFAULT_NEW_NAME },
      },
    ])
  }
  return (
    <button
      type="button"
      className="subfield-add"
      onClick={onAdd}
      aria-label="Add"
      title={`New Page / New ${containerLabel}`}
    >
      <Icon name="plus" size="sm" />
    </button>
  )
}

/** List ⇄ Gallery toggle for NavView (the `none` empty state) — drives the persisted `navViewMode`
 *  slice (separate from NavWindow's `navWindowMode`). Mirrors the NavWindow rail toggle's markup. */
function ViewTypeItem(): React.JSX.Element {
  const mode = useSession((s) => s.navViewMode)
  const setMode = useSession((s) => s.setNavViewMode)
  return (
    <button
      type="button"
      className="subfield-viewtype"
      onClick={() => setMode(mode === 'list' ? 'gallery' : 'list')}
      title={mode === 'list' ? 'Switch to Gallery' : 'Switch to List'}
    >
      <Icon name="chevrons-up-down" size="sm" />
      <span>{mode === 'list' ? 'List' : 'Gallery'}</span>
    </button>
  )
}

export function SubfieldItem({
  id,
  scope,
}: { id: SubfieldItemId } & SubfieldItemProps): React.JSX.Element | null {
  switch (id) {
    case 'pageStats':
      return <PageStatsItem scope={scope} />
    case 'addMenu':
      return <AddMenuItem />
    case 'viewType':
      return <ViewTypeItem />
  }
}
