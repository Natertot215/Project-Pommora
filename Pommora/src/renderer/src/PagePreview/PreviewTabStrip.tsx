import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { cx } from '@renderer/design-system/cx'
import { Icon } from '@renderer/design-system/symbols'
import { duration, text } from '@renderer/design-system/tokens'
import { EntityGlyph } from '../Navigation/EntityGlyph'
import { resolveWith, type ResolveIndex, type ResolvedNav } from '../Navigation/navResolve'
import { useExitPresence } from '../design-system/useExitPresence'
import { useSession } from '../store'
import type { PreviewTab } from './previewTabs'
import '../Tabs/tabStrip.css'

const BASE_MS = Number.parseInt(duration.base, 10)
/** The tab close/open width window — the toolbar strip's EXIT_MS twin (base + the segment's
 *  delayed exit). */
const EXIT_MS = BASE_MS + Number.parseInt(duration.fast, 10)
const TAB_ICON = 12

interface Entry {
  tab: PreviewTab
  res: ResolvedNav | null
}

/** The preview toolbar's center region — the H-9 morph owner. One tab renders the centered
 *  breadcrumb title (inert, F-2); a second tab's birth swaps it for the left-aligned strip on the
 *  shared tab-open motion (tabs grow via tabStrip.css's @starting-style; the title fades/slides
 *  left on the same tokens, held through its exit). Ghost-closing keeps the strip mounted so the
 *  last collapse plays before the title returns. */
export function PreviewTabStrip({
  index,
  title,
}: {
  index: ResolveIndex | null
  title: React.ReactNode
}): React.JSX.Element {
  const preview = useSession((s) => s.preview)
  const activatePreviewTab = useSession((s) => s.activatePreviewTab)
  const closePreviewTab = useSession((s) => s.closePreviewTab)
  const tabs = preview?.tabs
  const activeTabId = preview?.activeTabId

  const entries = useMemo<Entry[]>(
    () =>
      (tabs ?? []).map((tab) => ({
        tab,
        res: tab.target.kind === 'page' && index ? resolveWith(index, tab.target) : null,
      })),
    [tabs, index],
  )

  // Store-first close with a rendered ghost for the width-collapse exit (the toolbar's J-6 pattern).
  const [ghosts, setGhosts] = useState<ReadonlyMap<string, { entry: Entry; index: number }>>(
    new Map(),
  )
  const requestClose = (id: string): void => {
    const i = entries.findIndex((e) => e.tab.id === id)
    const entry = entries[i]
    if (!entry) return
    setGhosts((m) => new Map(m).set(id, { entry, index: i }))
    closePreviewTab(id)
    setTimeout(() => {
      setGhosts((m) => {
        const next = new Map(m)
        next.delete(id)
        return next
      })
    }, EXIT_MS)
  }
  const renderEntries = useMemo<{ entry: Entry; ghost: boolean }[]>(() => {
    const live = entries
      .filter((e) => !ghosts.has(e.tab.id))
      .map((entry) => ({ entry, ghost: false }))
    for (const [, g] of [...ghosts.entries()].sort((a, b) => a[1].index - b[1].index)) {
      live.splice(Math.min(g.index, live.length), 0, { entry: g.entry, ghost: true })
    }
    return live
  }, [entries, ghosts])
  const firstLive = renderEntries.findIndex((e) => !e.ghost)

  const showStrip = (tabs?.length ?? 0) > 1 || ghosts.size > 0
  const titlePresence = useExitPresence(!showStrip)
  // The exiting title fades out as WHAT IT WAS — crumbs re-derive from the new active tab, so the
  // live node would swap text mid-collapse without this hold.
  const heldTitle = useRef(title)
  if (!showStrip) heldTitle.current = title

  // The active tab scrolls into view on switch (the toolbar's J-5 rule).
  const scrollRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!activeTabId) return
    scrollRef.current
      ?.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(activeTabId)}"]`)
      ?.scrollIntoView({ inline: 'nearest', block: 'nearest' })
  }, [activeTabId])

  return (
    <>
      {titlePresence.mounted && (
        <div className={cx('pgpreview-title', titlePresence.closing && 'is-collapsing')}>
          {titlePresence.closing ? heldTitle.current : title}
        </div>
      )}
      <div className="pgpreview-tabwrap">
        {showStrip && (
          <div className="pgpreview-tabscroll edge-fade-x" ref={scrollRef}>
            <div className="pgpreview-tabstrip">
              {renderEntries.map(({ entry, ghost }, i) => (
                <Fragment key={entry.tab.id}>
                  {i > 0 && (
                    <span
                      className={cx('tab-seg', (ghost || i === firstLive) && 'is-closing')}
                      aria-hidden
                    />
                  )}
                  <PreviewTabItem
                    entry={entry}
                    active={!ghost && entry.tab.id === activeTabId}
                    closing={ghost}
                    onActivate={() => activatePreviewTab(entry.tab.id)}
                    onClose={() => requestClose(entry.tab.id)}
                  />
                </Fragment>
              ))}
            </div>
          </div>
        )}
      </div>
    </>
  )
}

function PreviewTabItem({
  entry,
  active,
  closing,
  onActivate,
  onClose,
}: {
  entry: Entry
  active: boolean
  closing: boolean
  onActivate: () => void
  onClose: () => void
}): React.JSX.Element {
  const isMap = entry.tab.target.kind === 'navwindow'
  const label = isMap ? 'Navigation' : (entry.res?.title ?? '')
  return (
    <div
      data-tab-id={entry.tab.id}
      className={cx('tab', text.caption.standard, active && 'is-active', closing && 'is-closing')}
      title={label}
      onClick={onActivate}
    >
      {entry.res ? (
        <EntityGlyph item={entry.res} size={TAB_ICON} className="tab-icon" />
      ) : (
        <Icon name={isMap ? 'map' : 'file'} size={TAB_ICON} className="tab-icon" />
      )}
      <span className="tab-label">{label}</span>
      {/* The map tab is perma-pinned (H-2) — no ×; the model refuses the close anyway. */}
      {!isMap && (
        <button
          type="button"
          className="tab-x"
          aria-label="Close Tab"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation()
            onClose()
          }}
        >
          <Icon name="x" size={10} strokeWidth={3} />
        </button>
      )}
    </div>
  )
}
