import { useSession } from '../store'

// Switches on the current selection. Vault and page bodies are deliberate
// placeholders — later stages replace them with the views table/gallery and
// the page render. The page branch already reflects the on-demand detail fetch
// (store.pageStatus) so the wiring is real, only the final render is stubbed.
export function DetailPane(): React.JSX.Element {
  const selection = useSession((s) => s.selection)

  switch (selection.kind) {
    case 'none':
      return (
        <div className="detail detail-empty">
          <span>Select a vault or page</span>
        </div>
      )
    case 'vault':
      return (
        <div className="detail">
          <div className="detail-placeholder">Views (table / gallery) — coming next</div>
        </div>
      )
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
