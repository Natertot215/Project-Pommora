import { SegmentedButton, type Segment } from '@renderer/design-system/components/Segmented-Controls'
import { useSession } from '../store'
import { navKey } from '../Navigation/navRecents'
import { useNavData } from '../Navigation/useNavData'
import './tabBarPreview.css'

// TEMPORARY multi-tab preview — a throwaway visual of a tab strip in the toolbar that tracks recent
// opens as tabs: current = label-secondary, others = label-tertiary, flex-width, icon + label per tab,
// segment dividers between. NOT a real feature — remove wholesale once the multi-tab direction settles.
const TAB_CAP = 8 // preview only — keep tabs legible; a real multi-tab model would page/scroll instead.

export function TabBarPreview(): React.JSX.Element | null {
  const { resolvedRecents, go } = useNavData()
  const selection = useSession((s) => s.selection)
  if (resolvedRecents.length === 0) return null

  const activeKey = selection.kind !== 'none' ? navKey(selection) : null
  const tabs: Segment[] = resolvedRecents.slice(0, TAB_CAP).map((r) => ({
    icon: r.icon,
    label: r.title,
    title: r.title,
    active: r.key === activeKey,
    onClick: () => go(r.target)
  }))
  return (
    <div className="tabbar-preview">
      <SegmentedButton segments={tabs} glass={false} className="tabbar-preview-seg" />
    </div>
  )
}
