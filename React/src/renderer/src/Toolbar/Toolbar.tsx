import { useRef, useState } from 'react'
import { SegmentedSymbol, type Segment } from '@renderer/design-system/components/Segmented-Controls'
import { Popover, useDismiss } from '@renderer/design-system/components/Popover'
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
  const trioRef = useRef<HTMLDivElement>(null)
  useDismiss(trioRef, () => setPanel(null), panel !== null)

  const toggle = (p: TrioPanel): void => setPanel((cur) => (cur === p ? null : p))

  // Back/Forward — rendered as recessed (label-secondary) control glyphs this pass;
  // inert until the navigation-history stack lands.
  const backForward: Segment[] = [
    { icon: 'chevron-left', title: 'Back' },
    { icon: 'chevron-right', title: 'Forward' }
  ]
  const trio: Segment[] = [
    { icon: 'map', title: 'Navigation', onClick: () => toggle('navigation'), active: panel === 'navigation' },
    { icon: 'sliders-horizontal', title: 'Settings', onClick: () => toggle('settings'), active: panel === 'settings' },
    { icon: 'panel-right', title: 'Inspector', onClick: onToggleInspector, active: inspectorOpen }
  ]

  return (
    <div className="app-toolbar">
      <div className="app-toolbar-cluster app-toolbar-cluster--nav">
        <SegmentedSymbol segments={backForward} paddingX="6px" />
      </div>
      <div className="app-toolbar-cluster" ref={trioRef}>
        <SegmentedSymbol segments={trio} />
        {panel === 'navigation' && (
          <Popover>
            <div className="toolbar-panel-stub">Navigation</div>
          </Popover>
        )}
        {panel === 'settings' && (
          <Popover>
            <div className="toolbar-panel-stub">Settings</div>
          </Popover>
        )}
      </div>
    </div>
  )
}
