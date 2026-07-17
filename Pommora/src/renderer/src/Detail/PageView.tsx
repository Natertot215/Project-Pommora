import { useEffect, useMemo, useRef, useState } from 'react'
import { useSession } from '../store'
import { MarkdownEditor } from '../MarkdownPM'
import {
  buildPageIndex,
  flattenPages,
  type ConnectionsApi,
  type ConnPage,
} from '../MarkdownPM/connections'
import { ConnectionMenu } from '../Embeds/ConnectionMenu'
import { IconPicker } from '../Components/IconPicker'
import { navKey } from '../Navigation/navRecents'
import { captureWarm, readWarm } from '../Tabs/warmCache'
import { registerPageFlush } from './pageFlush'

const SAVE_DEBOUNCE_MS = 400
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
  const setLiveBody = useSession((s) => s.setLiveBody)
  const pendingSave = useRef<
    { path: string; body: string; timer: ReturnType<typeof setTimeout> } | undefined
  >(undefined)
  const liveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)

  const [connMenu, setConnMenu] = useState<{ page: ConnPage; x: number; y: number } | null>(null)
  const connections = useMemo<ConnectionsApi | undefined>(() => {
    if (!tree) return undefined
    const idx = buildPageIndex(flattenPages(tree))
    return {
      ...idx,
      open: (page) => void select({ kind: 'page', id: page.id, path: page.path }),
      menu: (page, at) => setConnMenu({ page, ...at }),
    }
  }, [tree, select])

  // The pending save is per-path: rescheduling the SAME page replaces its timer (normal typing debounce),
  // but a different page's schedule FLUSHES the pending write first — clearing it would silently drop the
  // previous page's last edits (the timer is shared across switches because PageView never remounts).
  const flushSave = (): void => {
    const p = pendingSave.current
    if (!p) return
    clearTimeout(p.timer)
    pendingSave.current = undefined
    void window.nexus.updatePageBody(p.path, p.body)
  }
  // A pending debounced save must survive teardown, not die with it: switching page→collection unmounts
  // PageView, and closing the window tears down the renderer — both within the 400ms window would otherwise
  // silently drop the last edit. Flush on unmount and on window close. (Page→page keeps PageView mounted;
  // scheduleSave's per-path flush covers that path.)
  const flushRef = useRef(flushSave)
  flushRef.current = flushSave
  useEffect(() => {
    const onUnload = (): void => flushRef.current()
    window.addEventListener('beforeunload', onUnload)
    // The adopt path flushes the pending write to the OLD root before flipping (registerPageFlush) — the
    // unmount-flush below then finds nothing to write into the new nexus.
    registerPageFlush(async () => {
      const p = pendingSave.current
      if (!p) return
      clearTimeout(p.timer)
      pendingSave.current = undefined
      await window.nexus.updatePageBody(p.path, p.body)
    })
    return () => {
      window.removeEventListener('beforeunload', onUnload)
      registerPageFlush(null)
      flushRef.current()
    }
  }, [])
  const scheduleSave = (path: string, body: string): void => {
    if (pendingSave.current) {
      if (pendingSave.current.path !== path) flushSave()
      else clearTimeout(pendingSave.current.timer)
    }
    const timer = setTimeout(() => {
      pendingSave.current = undefined
      void window.nexus.updatePageBody(path, body)
    }, SAVE_DEBOUNCE_MS)
    pendingSave.current = { path, body, timer }
  }
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
              scheduleSave(pageDetail.path, body)
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
          {connMenu && <ConnectionMenu {...connMenu} onClose={() => setConnMenu(null)} />}
        </>
      )
  }
}
