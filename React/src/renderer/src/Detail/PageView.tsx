import { useMemo, useRef } from 'react'
import { useSession } from '../store'
import { MarkdownEditor } from '../MarkdownPM'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'

/** Idle window before an edit flushes to disk. */
const SAVE_DEBOUNCE_MS = 400

/**
 * The page detail body — hosts the MarkdownPM editor over the open page's body. Edits debounce out
 * to a frontmatter-preserving main-side write; the editor keys on the path so it remounts per page.
 * (Swift: Pages/PageEditorView.)
 */
export function PageView(): React.JSX.Element {
  const pageStatus = useSession((s) => s.pageStatus)
  const pageDetail = useSession((s) => s.pageDetail)
  const pageError = useSession((s) => s.pageError)
  const submitRename = useSession((s) => s.submitRename)
  const tree = useSession((s) => s.tree)
  const select = useSession((s) => s.select)
  const saveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return { ...idx, open: (page) => void select({ kind: 'page', id: page.id, path: page.path }) }
  }, [tree, select])

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
          onRename={(newName) => submitRename(pageDetail.path, 'page', newName)}
          onChange={(body) => scheduleSave(pageDetail.path, body)}
          connections={connections}
        />
      )
  }
}
