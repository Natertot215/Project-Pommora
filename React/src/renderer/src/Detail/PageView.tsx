import { useMemo, useRef, useState } from 'react'
import { useSession } from '../store'
import { MarkdownEditor } from '../MarkdownPM'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'
import { IconPicker } from '../Components/IconPicker'
import { asIconName } from '../design-system/symbols'

const SAVE_DEBOUNCE_MS = 400
// Live stats settle just behind the keystroke so a long page isn't Markdown-scanned on every char.
const STATS_DEBOUNCE_MS = 120

export function PageView(): React.JSX.Element {
  const pageStatus = useSession((s) => s.pageStatus)
  const pageDetail = useSession((s) => s.pageDetail)
  const pageError = useSession((s) => s.pageError)
  const submitRename = useSession((s) => s.submitRename)
  const tree = useSession((s) => s.tree)
  const select = useSession((s) => s.select)
  const setLiveBody = useSession((s) => s.setLiveBody)
  const saveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const liveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)

  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return { ...idx, open: (page) => void select({ kind: 'page', id: page.id, path: page.path }) }
  }, [tree, select])

  const debounce = (ref: typeof saveTimer, fn: () => void, ms: number): void => {
    if (ref.current) clearTimeout(ref.current)
    ref.current = setTimeout(fn, ms)
  }
  // saveTimer persists the body (400ms); liveTimer feeds the Subfield stats buffer on a shorter
  // cadence (120ms) so a long page isn't re-scanned per keystroke. Two timers, two distinct cadences.
  const scheduleSave = (path: string, body: string): void =>
    debounce(saveTimer, () => void window.nexus.updatePageBody(path, body), SAVE_DEBOUNCE_MS)
  const pushLiveBody = (path: string, body: string): void =>
    debounce(liveTimer, () => setLiveBody(path, body), STATS_DEBOUNCE_MS)

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
        <>
          <MarkdownEditor
            key={pageDetail.path}
            initialBody={pageDetail.body}
            title={pageDetail.title}
            path={pageDetail.path}
            icon={asIconName(pageDetail.frontmatter.icon)}
            cover={typeof pageDetail.frontmatter.cover === 'string' ? pageDetail.frontmatter.cover : undefined}
            onEditIcon={() => setIconPickerOpen(true)}
            onRename={(newName) => submitRename(pageDetail.path, 'page', newName)}
            onChange={(body) => {
              pushLiveBody(pageDetail.path, body) // debounced live buffer → Subfield stats
              scheduleSave(pageDetail.path, body)
            }}
            connections={connections}
            folds={{
              load: async () => (await window.nexus.folds.get())[pageDetail.id] ?? [],
              save: (keys) => void window.nexus.folds.set(pageDetail.id, keys)
            }}
            tableHeadingColumns={{
              load: async () => (await window.nexus.tableHeadingColumns.get())[pageDetail.id] ?? [],
              save: (indices) => void window.nexus.tableHeadingColumns.set(pageDetail.id, indices)
            }}
            menu={{
              pushState: (s) => window.nexus.setEditorFormatState(s),
              onAction: (cb) => window.nexus.onMenuAction(cb)
            }}
          />
          <IconPicker open={iconPickerOpen} onClose={() => setIconPickerOpen(false)} />
        </>
      )
  }
}
