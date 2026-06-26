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
export type SubfieldItemId = 'pageStats' | 'addMenu'

const ALL_ITEM_IDS: SubfieldItemId[] = ['pageStats', 'addMenu']
/** Narrow a persisted (untrusted) id string to a known item id — drops stale/unknown entries. */
export function isSubfieldItemId(id: string): id is SubfieldItemId {
  return (ALL_ITEM_IDS as string[]).includes(id)
}

export const DEFAULT_ITEMS: Record<SelectionState['kind'], SubfieldItemId[]> = {
  none: [],
  homepage: [],
  context: [],
  collection: ['addMenu'],
  set: ['addMenu'],
  page: ['pageStats']
}

/** Lines · Words · Characters for the open page (from the loaded body). */
function PageStatsItem(): React.JSX.Element {
  const pageDetail = useSession((s) => s.pageDetail)
  const stats = useMemo(() => computeStats(pageDetail?.body ?? ''), [pageDetail?.body])
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
    void window.nexus.popCreateMenu([
      { label: 'New Page', req: { op: 'createPage', parentPath, name: DEFAULT_NEW_NAME } },
      { label: `New ${containerLabel}`, req: { op: 'createContainer', parentPath, kind: 'set', name: DEFAULT_NEW_NAME } }
    ])
  }
  return (
    <button type="button" className="subfield-add" onClick={onAdd} aria-label="Add" title={`New Page / New ${containerLabel}`}>
      <Icon name="square-plus" size="sm" />
    </button>
  )
}

export function SubfieldItem({ id }: { id: SubfieldItemId }): React.JSX.Element | null {
  switch (id) {
    case 'pageStats':
      return <PageStatsItem />
    case 'addMenu':
      return <AddMenuItem />
  }
}
