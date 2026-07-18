import { useMemo } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import { useSession } from '../../store'
import { useActiveView } from './useActiveView'
import { resolveContainerSchema, TableView } from './Table/TableView'
import { GalleryView } from './Gallery/GalleryView'

/**
 * The renderer seam — the ONE `view.type` switch, consumed by both TableView mounts (the
 * container detail pane and the SurfacePM view embed). A new view type adds its branch here
 * and nowhere else.
 */
export function ViewRenderer({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const schema = useMemo(() => (tree ? resolveContainerSchema(tree, source) : []), [tree, source])
  const { view } = useActiveView(source, schema)
  return view.type === 'gallery' ? (
    <GalleryView key={source.id} source={source} />
  ) : (
    <TableView key={source.id} source={source} />
  )
}
