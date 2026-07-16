import { Fragment, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import type { ResolvedNav } from '../Navigation/navResolve'
import { useSession } from '../store'
import { navKey } from '../Navigation/navRecents'
import { useNavData } from '../Navigation/useNavData'
import './tabBarPreview.css'

// TEMPORARY multi-tab preview — a throwaway toolbar tab strip exploring the multi-tab feel. Tabs hold a
// FIXED order (seeded from recents, new opens append to the right, existing tabs never reshuffle — real-tab
// behaviour, not jumping recents); the current tab reads label-control and a selection indicator SLIDES to
// it on change. Overflow-scrolls when full. NOT a real feature — remove wholesale once the direction settles.
export function TabBarPreview(): React.JSX.Element | null {
  const { resolvedRecents, go } = useNavData()
  const selection = useSession((s) => s.selection)
  const activeKey = selection.kind !== 'none' ? navKey(selection) : null

  const byKey = useMemo(() => new Map(resolvedRecents.map((r) => [r.key, r])), [resolvedRecents])
  const [tabs, setTabs] = useState<ResolvedNav[]>([])
  // Seed the fixed order once from the initial recents (reverse MRU → chronological, so new opens land right).
  useEffect(() => {
    setTabs((prev) => (prev.length > 0 || resolvedRecents.length === 0 ? prev : [...resolvedRecents].reverse()))
  }, [resolvedRecents])
  // A newly-opened entity becomes a new tab at the end — existing tabs never move.
  useEffect(() => {
    if (!activeKey) return
    const item = byKey.get(activeKey)
    if (item) setTabs((prev) => (prev.some((t) => t.key === activeKey) ? prev : [...prev, item]))
  }, [activeKey, byKey])

  // Slide the selection indicator to the active tab (measured in scroll-content coords), and scroll it in.
  const scrollRef = useRef<HTMLDivElement>(null)
  const [sel, setSel] = useState<{ left: number; width: number } | null>(null)
  useLayoutEffect(() => {
    const idx = activeKey ? tabs.findIndex((t) => t.key === activeKey) : -1
    const el = idx >= 0 ? scrollRef.current?.querySelectorAll<HTMLElement>('.tabbar-preview-tab')[idx] : undefined
    setSel(el ? { left: el.offsetLeft, width: el.offsetWidth } : null)
    el?.scrollIntoView({ inline: 'nearest', block: 'nearest' })
  }, [activeKey, tabs])

  if (tabs.length === 0) return null
  return (
    <div className="tabbar-preview">
      <div className="tabbar-preview-scroll" ref={scrollRef}>
        {sel && <div className="tabbar-preview-sel" style={{ transform: `translate(${sel.left}px, -50%)`, width: sel.width }} />}
        {tabs.map((t, i) => (
          <Fragment key={t.key}>
            {i > 0 && <span className="tabbar-preview-div" />}
            <button
              type="button"
              className={cx('tabbar-preview-tab', text.control.standard, t.key === activeKey && 'is-active')}
              onClick={() => go(t.target)}
              title={t.title}
            >
              <Icon name={t.icon} size={14} className="tabbar-preview-tab-icon" />
              <span className="tabbar-preview-tab-label">{t.title}</span>
            </button>
          </Fragment>
        ))}
      </div>
    </div>
  )
}
