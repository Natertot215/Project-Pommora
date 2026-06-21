import { useSession } from '../store'
import { findVault, findCollection } from './Scope'
import { ContainerView } from './ContainerView'
import { HomepageView } from './HomepageView'
import { ContextView } from './ContextView'
import { PageView } from './PageView'

/**
 * Routes the current selection to its view. Vault + Collection share ContainerView (same view
 * principles); Homepage and Context have their own; Page is a placeholder. (Swift: SidebarDetailView.)
 */
export function DetailPane(): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const tree = useSession((s) => s.tree)

  switch (selection.kind) {
    case 'none':
      return (
        <div className="detail detail-empty">
          <span>Select a vault or page</span>
        </div>
      )
    case 'homepage':
      return <HomepageView tree={tree} />
    case 'context':
      return <ContextView tree={tree} id={selection.id} />
    case 'vault': {
      const vault = findVault(tree, selection.id)
      return vault ? (
        <ContainerView source={vault} />
      ) : (
        <div className="detail">
          <div className="detail-placeholder">Vault not found</div>
        </div>
      )
    }
    case 'collection': {
      const col = findCollection(tree, selection.id)
      return col ? (
        <ContainerView source={col} />
      ) : (
        <div className="detail">
          <div className="detail-placeholder">Collection not found</div>
        </div>
      )
    }
    case 'page':
      return (
        <div className="detail detail-page">
          <PageView />
        </div>
      )
  }
}
