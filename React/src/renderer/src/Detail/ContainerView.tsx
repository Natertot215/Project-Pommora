import type { CollectionNode, SetNode } from '@shared/types'
import { DetailScaffold } from './DetailScaffold'
import { TableView } from './Table/TableView'
import { containerOwner } from './Scope'

/**
 * The shared view for the two page containers — Collection and (depth-1) Set — which use the same
 * principles: a banner over the container's pages in a table. `source.kind` is the seam for any
 * container-specific divergence. (Swift: PageCollectionDetailView + PageSetDetailView, both thin
 * entries over one ViewSurface/DetailScope.)
 */
export function ContainerView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  return (
    <DetailScaffold owner={containerOwner(source)}>
      <TableView source={source} />
    </DetailScaffold>
  )
}
