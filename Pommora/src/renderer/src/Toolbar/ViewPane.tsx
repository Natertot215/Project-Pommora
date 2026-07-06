import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { mintNewView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { Menu, MenuItem, MenuBottomRow, AccessoryButton } from '../design-system/components/menu'
import { dropdownRowTitle, side } from '../design-system/components/menu/menu.css'
import { useSession } from '../store'

/**
 * The ViewPane — the navigation dropdown the ViewDropdown discloses. A row per saved view (click
 * switches the active view + closes; the chevron will push into ViewSettings) over a footer BottomRow
 * (+ create · … more). Reorder + the chevron push land in the ViewSettings pass.
 */
export function ViewPane({
  node,
  schema,
  onClose
}: {
  node: CollectionNode | SetNode
  schema: PropertyDefinition[]
  onClose: () => void
}): React.JSX.Element {
  const setActiveView = useSession((s) => s.setActiveView)
  const load = useSession((s) => s.load)
  const activeViewId = useSession((s) => s.activeViews[node.id])
  const views = node.views ?? []

  const switchTo = async (id: string): Promise<void> => {
    await setActiveView(node.id, id)
    onClose()
  }
  const createView = async (): Promise<void> => {
    await window.nexus.views.save(node.path, node.kind, mintNewView('Untitled', schema))
    await load()
  }

  return (
    <Menu>
      {views.map((v) => (
        <MenuItem
          key={v.id}
          selected={v.id === activeViewId}
          leading={<Icon name={iconNameOr(v.icon, 'table')} size={16} />}
          trailing={
            <span className={side}>
              <Icon name="chevron-right" size={16} />
            </span>
          }
          onClick={() => void switchTo(v.id)}
        >
          <span className={dropdownRowTitle}>{v.name}</span>
        </MenuItem>
      ))}
      <MenuBottomRow
        leading={<AccessoryButton icon="plus" size={12} box={20} ariaLabel="New View" onClick={() => void createView()} />}
        trailing={<AccessoryButton icon="dots" size={12} box={20} ariaLabel="More" onClick={() => {}} />}
      />
    </Menu>
  )
}
