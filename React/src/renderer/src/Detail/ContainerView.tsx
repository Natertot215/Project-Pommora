import type { CollectionNode, PageTypeNode } from '@shared/types'
import { DetailScaffold } from './DetailScaffold'
import { TableView } from './Table/TableView'
import { containerOwner } from './Scope'

/**
 * The shared view for the two page containers — Vault (PageType) and Collection — which use the
 * same principles: a banner over the container's pages in a table. `source.kind` is the seam for
 * any container-specific divergence. (Swift: PageTypeDetailView + PageCollectionDetailView, both
 * thin entries over one ViewSurface/DetailScope.)
 */
export function ContainerView({ source }: { source: PageTypeNode | CollectionNode }): React.JSX.Element {
  return (
    <DetailScaffold owner={containerOwner(source)}>
      <TableView source={source} />
    </DetailScaffold>
  )
}
