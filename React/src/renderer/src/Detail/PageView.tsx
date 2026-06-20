import { useRef } from 'react'
import { useSession } from '../store'
import { MarkdownEditor } from '../MarkdownPM'

/** Idle window before an edit flushes to disk. */
const SAVE_DEBOUNCE_MS = 400

/**
 * The page detail body — hosts the MarkdownPM editor over the open page's Markdown body.
 * Edits debounce out to `page:updateBody` (frontmatter-preserving, main-side). The editor keys
 * on the page path so it remounts cleanly per page. (Swift: Pages/PageEditorView.)
 */
export function PageView(): React.JSX.Element {
  const pageStatus = useSession((s) => s.pageStatus)
  const pageDetail = useSession((s) => s.pageDetail)
  const pageError = useSession((s) => s.pageError)
  const submitRename = useSession((s) => s.submitRename)
  const saveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  const scheduleSave = (path: string, body: string): void => {
    if (saveTimer.current) clearTimeout(saveTimer.current)
    saveTimer.current = setTimeout(() => {
      void window.nexus.updatePageBody(path, body)
    }, SAVE_DEBOUNCE_MS)
  }

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
      if (!pageDetail) return <div className="detail-placeholder">Page render — coming next</div>
      return (
        <MarkdownEditor
          key={pageDetail.path}
          initialBody={pageDetail.body}
          title={pageDetail.title}
          onRename={(newName) => void submitRename(pageDetail.path, 'page', newName)}
          onChange={(body) => scheduleSave(pageDetail.path, body)}
        />
      )
  }
}
