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
// FIXED order (seeded from recents, new opens append right, existing tabs never reshuffle — real-tab
// behaviour, not jumping recents). The current tab reads label-control: a clipped bright DUPLICATE of the
// strip sits over the dim base, and sliding its clip to the active tab slides the highlight across (no fill,
// just the label colour). Overflow-scrolls with an inline edge fade. NOT a real feature — remove wholesale.
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

  // Slide the bright layer's clip to the active tab (measured from the base track in stack coords) + scroll
  // it into view. clip-path transitions on --duration-base, so the highlight sweeps across on change.
  const stackRef = useRef<HTMLDivElement>(null)
  const baseRef = useRef<HTMLDivElement>(null)
  const [clip, setClip] = useState('inset(0 100% 0 0)')
  useLayoutEffect(() => {
    const idx = activeKey ? tabs.findIndex((t) => t.key === activeKey) : -1
    const el = idx >= 0 ? baseRef.current?.querySelectorAll<HTMLElement>('.tabbar-preview-tab')[idx] : undefined
    const stackW = stackRef.current?.offsetWidth ?? 0
    if (el && stackW) {
      setClip(`inset(0 ${Math.max(0, stackW - el.offsetLeft - el.offsetWidth)}px 0 ${el.offsetLeft}px)`)
      el.scrollIntoView({ inline: 'nearest', block: 'nearest' })
    }
  }, [activeKey, tabs])

  if (tabs.length === 0) return null
  const strip = (interactive: boolean): React.JSX.Element[] =>
    tabs.map((t, i) => (
      <Fragment key={t.key}>
        {i > 0 && <span className="tabbar-preview-div" />}
        <button
          type="button"
          className={cx('tabbar-preview-tab', text.control.standard)}
          onClick={interactive ? () => go(t.target) : undefined}
          tabIndex={interactive ? undefined : -1}
          title={interactive ? t.title : undefined}
        >
          <Icon name={t.icon} size={14} className="tabbar-preview-tab-icon" />
          <span className="tabbar-preview-tab-label">{t.title}</span>
        </button>
      </Fragment>
    ))
  return (
    <div className="tabbar-preview">
      <div className="tabbar-preview-scroll">
        <div className="tabbar-preview-stack" ref={stackRef}>
          <div className="tabbar-preview-track" ref={baseRef}>
            {strip(true)}
          </div>
          <div className="tabbar-preview-track tabbar-preview-hi" aria-hidden style={{ clipPath: clip }}>
            {strip(false)}
          </div>
        </div>
      </div>
    </div>
  )
}
