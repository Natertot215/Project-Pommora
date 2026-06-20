import { useSession } from '../store'

/**
 * The page detail body — a deliberate placeholder; a later stage replaces it with the page render.
 * It already reflects the on-demand fetch (store.pageStatus) so the wiring is real, only the final
 * render is stubbed. (Swift: Pages/PageEditorView.)
 */
export function PageView(): React.JSX.Element {
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
