import { useEffect, useMemo, useRef, useState } from 'react'
import { useSession } from '../store'
import { MarkdownEditor } from '../MarkdownPM'
import { buildPageIndex, flattenPages, type ConnectionsApi } from '../MarkdownPM/connections'
import { showConnectionMenu } from '../Embeds/connectionMenu'
import { useConnectionHover } from '../Embeds/ConnectionHoverCard'
import { IconPicker } from '../Components/IconPicker'
import { navKey } from '../Navigation/navRecents'
import { captureWarm, readWarm } from '../Tabs/warmCache'
import { schedulePageSave } from './pageFlush'

// Live stats settle just behind the keystroke so a long page isn't Markdown-scanned on every char.
const STATS_DEBOUNCE_MS = 120

export function PageView(): React.JSX.Element {
  const pageStatus = useSession((s) => s.pageStatus)
  const pageDetail = useSession((s) => s.pageDetail)
  const activeTabId = useSession((s) => s.activeTabId)
  const pageError = useSession((s) => s.pageError)
  const submitRename = useSession((s) => s.submitRename)
  const mutate = useSession((s) => s.mutate)
  const tree = useSession((s) => s.tree)
  const select = useSession((s) => s.select)
  const openPreview = useSession((s) => s.openPreview)
  // B-6 reads the LIVE personalization slice (setPersonalization updates it before the tree echoes).
  const openInPreview = useSession((s) => s.personalization.connectionsOpenInPreview ?? false)
  const setLiveBody = useSession((s) => s.setLiveBody)
  const liveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)

  const { hover, card: hoverCard } = useConnectionHover()
  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return {
      ...idx,
      open: (page) =>
        openInPreview
          ? openPreview({ id: page.id, path: page.path })
          : void select({ kind: 'page', id: page.id, path: page.path }),
      bypass: (page) =>
        void select({ kind: 'page', id: page.id, path: page.path }, { newTab: true }),
      hover,
      menu: showConnectionMenu,
    }
  }, [tree, select, openPreview, openInPreview, hover])

  // The debounced body write lives in the shared path-keyed autosave (pageFlush) — teardown paths
  // (unmount inside the debounce, window close, nexus adopt) all flush THERE, so a pending write
  // survives this component without any per-host flush machinery.
  const pushLiveBody = (path: string, body: string): void => {
    if (liveTimer.current) clearTimeout(liveTimer.current)
    liveTimer.current = setTimeout(() => setLiveBody(path, body), STATS_DEBOUNCE_MS)
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
        <>
          {hoverCard}
          <MarkdownEditor
            key={pageDetail.path}
            initialBody={pageDetail.body}
            title={pageDetail.title}
            path={pageDetail.path}
            cover={
              typeof pageDetail.frontmatter.cover === 'string'
                ? pageDetail.frontmatter.cover
                : undefined
            }
            onEditIcon={() => setIconPickerOpen(true)}
            onRename={(newName) => submitRename(pageDetail.path, 'page', newName)}
            onChange={(body) => {
              pushLiveBody(pageDetail.path, body) // debounced live buffer → Subfield stats
              schedulePageSave(pageDetail.path, body)
            }}
            connections={connections}
            folds={{
              load: async () => (await window.nexus.folds.get())[pageDetail.id] ?? [],
              save: (keys) => void window.nexus.folds.set(pageDetail.id, keys),
            }}
            tableHeadingColumns={{
              load: async () => (await window.nexus.tableHeadingColumns.get())[pageDetail.id] ?? [],
              save: (indices) => void window.nexus.tableHeadingColumns.set(pageDetail.id, indices),
            }}
            menu={{
              pushState: (s) => window.nexus.setEditorFormatState(s),
              onAction: (cb) => window.nexus.onMenuAction(cb),
            }}
            // The editor freezes this at mount, so the capture lands under the tab that OWNED this
            // page even though activeTabId moves before the unmount (select switches synchronously).
            // restore carries the store's rename fence: a warm entry whose captured path diverges from
            // the mounting page's mounts cold (id-keyed warmth must never revive a stale-path doc).
            warm={{
              restore: () => {
                const entry = readWarm(
                  activeTabId,
                  navKey({ kind: 'page', id: pageDetail.id, path: pageDetail.path }),
                )
                return entry?.pageDetail?.path === pageDetail.path ? entry : undefined
              },
              capture: (state) =>
                captureWarm(
                  activeTabId,
                  navKey({ kind: 'page', id: pageDetail.id, path: pageDetail.path }),
                  state,
                ),
            }}
          />
          <IconPicker
            open={iconPickerOpen}
            onClose={() => setIconPickerOpen(false)}
            value={
              typeof pageDetail.frontmatter.icon === 'string'
                ? pageDetail.frontmatter.icon
                : undefined
            }
            onSelect={(id) =>
              void mutate({ op: 'setIcon', path: pageDetail.path, kind: 'page', icon: id })
            }
          />
        </>
      )
  }
}
