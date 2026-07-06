import { useEffect, useRef, useState } from 'react'
import { SegmentedSymbol, type Segment } from '@renderer/design-system/components/Segmented-Controls'
import { useDismiss } from '@renderer/design-system/components/Popover'
import { MenuSurface } from '@renderer/design-system/components/menu'
import { ToolbarTrio } from './ToolbarTrio'
import { ViewDropdown } from './ViewDropdown'
import { SettingsDropdown } from '../Components/Detail/SettingsDropdown'
import * as dropdown from '../Components/Detail/settingsPane.css'
import { useSession } from '../store'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import './toolbar.css'

type TrioPanel = 'navigation' | 'settings'

/**
 * The two persistent toolbar clusters, floated in the top window strip:
 * Back/Forward (leading) and the Navigation · Settings · Inspector trio (trailing).
 * The only always-in-view chrome; each button's behaviour/content depends on the
 * active view (Navigation + Settings are stub panels for now).
 */
export function Toolbar({
  inspectorOpen,
  onToggleInspector
}: {
  inspectorOpen: boolean
  onToggleInspector: () => void
}): React.JSX.Element {
  const [panel, setPanel] = useState<TrioPanel | null>(null)
  const [trioW, setTrioW] = useState(0)
  const trioRef = useRef<HTMLDivElement>(null)
  useDismiss(trioRef, () => setPanel(null), panel !== null)
  // Each dropdown stays mounted through its retract animation before leaving the DOM.
  const navP = useExitPresence(panel === 'navigation')
  const settingsP = useExitPresence(panel === 'settings')

  // Publish the pill's measured width so the ride math (toolbar.css) knows where the trio's left edge
  // sits — it lands flush at the inspector's left corner. offsetWidth ignores the ride transform.
  useEffect(() => {
    const el = trioRef.current
    if (!el) return
    const apply = (): void => {
      el.style.setProperty('--trio-w', `${el.offsetWidth}px`)
      setTrioW(el.offsetWidth)
    }
    apply()
    const ro = new ResizeObserver(apply)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const toggle = (p: TrioPanel): void => setPanel((cur) => (cur === p ? null : p))

  const goBack = useSession((s) => s.goBack)
  const goForward = useSession((s) => s.goForward)
  const canGoBack = useSession((s) => s.navIndex > 0)
  const canGoForward = useSession((s) => s.navIndex < s.navStack.length - 1)

  // Back/Forward walk the store's navigation history (disabled at each end).
  const backForward: Segment[] = [
    { icon: 'chevron-left', title: 'Back', onClick: goBack, disabled: !canGoBack },
    { icon: 'chevron-right', title: 'Forward', onClick: goForward, disabled: !canGoForward }
  ]
  const trio: Segment[] = [
    { icon: 'map', title: 'Navigation', onClick: () => toggle('navigation'), active: panel === 'navigation' },
    { icon: 'sliders-horizontal', title: 'Settings', onClick: () => toggle('settings'), active: panel === 'settings' },
    { icon: 'panel-right', title: 'Inspector', onClick: onToggleInspector, active: inspectorOpen }
  ]

  return (
    <div className="app-toolbar">
      <div className="app-toolbar-cluster app-toolbar-cluster--nav">
        <SegmentedSymbol segments={backForward} paddingX="6px" iconSize="lg" />
      </div>
      <div className="app-toolbar-right">
        <ViewDropdown />
        <div className="app-toolbar-cluster app-toolbar-cluster--trio" ref={trioRef}>
          <ToolbarTrio segments={trio} />
        {/* Beak aim: the dropdowns hang right-aligned under the trio, so each notch is measured from
            the pane's right edge to its trigger's center — Navigation at 5/6 of the trio's width,
            Settings at dead center (3 equal segments). */}
        {navP.mounted && (
          <div className={dropdown.anchor}>
            <MenuSurface closing={navP.closing} notchInsetRight={trioW ? (trioW * 5) / 6 : undefined}>
              {/* Blank chrome until Navigation ships (no build-status copy — Guidelines/UI-Copy.md). */}
              <div style={{ minHeight: 24 }} />
            </MenuSurface>
          </div>
        )}
        {settingsP.mounted && (
          <SettingsDropdown closing={settingsP.closing} notchInsetRight={trioW ? trioW / 2 : undefined} />
        )}
        </div>
      </div>
    </div>
  )
}
