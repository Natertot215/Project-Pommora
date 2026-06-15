import type { NexusTree, PageTypeNode } from '@shared/types'
import { useSession } from '../store'
import { TableView } from '../views/TableView'

/** Find a vault (PageTypeNode) by id across the ungrouped vaults + user sections. */
function findVault(tree: NexusTree | null, id: string): PageTypeNode | undefined {
  if (!tree) return undefined
  const inDefault = tree.vaults.find((v) => v.id === id)
  if (inDefault) return inDefault
  for (const sec of tree.userSections) {
    const hit = sec.vaults.find((v) => v.id === id)
    if (hit) return hit
  }
  return undefined
}

// Switches on the current selection. The page body is a deliberate placeholder
// — a later stage replaces it with the page render. The page branch already
// reflects the on-demand detail fetch (store.pageStatus) so the wiring is real,
// only the final render is stubbed. The vault branch renders the table view.
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
    case 'vault': {
      const vault = findVault(tree, selection.id)
      return (
        <div className="detail">
          {vault ? (
            <TableView vault={vault} />
          ) : (
            <div className="detail-placeholder">Vault not found</div>
          )}
        </div>
      )
    }
    case 'page':
      return (
        <div className="detail">
          <PageDetailPlaceholder />
        </div>
      )
  }
}

function PageDetailPlaceholder(): React.JSX.Element {
  const pageStatus = useSession((s) => s.pageStatus)
  const pageDetail = useSession((s) => s.pageDetail)
  const pageError = useSession((s) => s.pageError)

  switch (pageStatus) {
    case 'idle':
    case 'loading':
      return <div className="detail-placeholder">Loading page…</div>
    case 'error':
      return (
        <div className="detail-placeholder detail-error">
          Couldn’t open page
          <span className="detail-detail">{pageError}</span>
        </div>
      )
    case 'ready':
      return (
        <div className="detail-placeholder">
          {pageDetail ? `Page: ${pageDetail.title} — render coming next` : 'Page render — coming next'}
        </div>
      )
  }
}
