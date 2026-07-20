import type { ReactNode } from 'react'
import type { CollectionNode, ResolvedGroup, SetNode } from '@shared/types'
import type { SavedView } from '@shared/views'
import { GroupBand, resolveBandHead } from '../GroupBand'
import { bandShowsAdd } from '../Cards/cardsBand'
import { useBandDrag } from './bandDnd'
import type { ResolveContext } from './resolveContext'

/** The table's band adapter: it holds the `useBandDrag` hook (which throws outside `<BandDnd>`, so it
 *  can't live in the shared presentational GroupBand) and the native Set context menu, then hands the
 *  resolved glyph + drag wiring to GroupBand. The disclosure body (rows + nested child bands) arrives
 *  as children. */
export function TableGroupBand({
  group,
  view,
  ctx,
  setNames,
  setIcons,
  source,
  setPath,
  onOpen,
  collapsed,
  onToggle,
  indent,
  children,
}: {
  group: ResolvedGroup
  view: SavedView
  ctx: ResolveContext
  setNames: Map<string, string>
  setIcons: Map<string, string | undefined>
  source: CollectionNode | SetNode
  /** The structural Set's real path — enables the native menu + inline rename (absent for property
   *  bands). */
  setPath?: string
  /** Present only for OPENABLE Sets (a Collection's direct children — sub-Sets are expand-only). */
  onOpen?: () => void
  collapsed: boolean
  onToggle: () => void
  indent: string
  children: ReactNode
}): React.JSX.Element {
  const dragHandle = useBandDrag(group.key)
  const { glyph } = resolveBandHead(group, view, ctx, setNames, setIcons, source, setPath)
  const onContextMenu = setPath
    ? (e: React.MouseEvent): void => {
        e.preventDefault()
        e.stopPropagation()
        void window.nexus.contextMenu({
          kind: 'set',
          path: setPath,
          title: setNames.get(group.key) ?? group.key,
        })
      }
    : undefined
  return (
    <GroupBand
      glyph={glyph}
      collapsed={collapsed}
      onToggle={onToggle}
      showAdd={bandShowsAdd(group.kind)}
      subBand={group.bucket !== undefined}
      indent={indent}
      dragHandle={dragHandle}
      onOpen={onOpen}
      onContextMenu={onContextMenu}
    >
      {children}
    </GroupBand>
  )
}
