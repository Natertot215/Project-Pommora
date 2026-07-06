import { useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { mintNewView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { Menu, MenuItem, MenuBottomRow, AccessoryButton } from '../design-system/components/menu'
import { dropdownRowTitle } from '../design-system/components/menu/menu.css'
import { PaneSlider } from '../Components/Detail/PaneSlider'
import { ViewSettings } from '../Components/Detail/ViewSettings'
import { useSession } from '../store'
import * as vd from './viewDropdown.css'

/**
 * The ViewPane — the navigation dropdown the ViewDropdown discloses. A row per saved view (click
 * switches the active view + closes; the chevron pushes into ViewSettings) over a footer BottomRow
 * (+ create · … more), the two levels riding one PaneSlider.
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
  const [editingId, setEditingId] = useState<string | null>(null)
  const views = node.views ?? []
  // Re-derive the edited view from the live tree so an edit (rename/type/format) shows fresh, not a
  // stale snapshot; a gone id (deleted) collapses back to the list.
  const editing = editingId ? views.find((v) => v.id === editingId) : undefined

  const switchTo = async (id: string): Promise<void> => {
    await setActiveView(node.id, id)
    onClose()
  }
  const createView = async (): Promise<void> => {
    await window.nexus.views.save(node.path, node.kind, mintNewView('Untitled', schema))
    await load()
  }

  const list = (
    <Menu className={vd.paneMenu}>
      {views.map((v) => (
        <MenuItem
          key={v.id}
          selected={v.id === activeViewId}
          leading={<Icon name={iconNameOr(v.icon, 'table')} size={16} />}
          trailing={
            <button
              type="button"
              aria-label={`Edit ${v.name}`}
              onClick={(e) => {
                e.stopPropagation()
                setEditingId(v.id)
              }}
              style={{ border: 'none', background: 'none', padding: 0, cursor: 'default', display: 'flex', color: 'var(--label-secondary)' }}
            >
              <Icon name="chevron-right" size={16} />
            </button>
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

  const detail = editing ? (
    <ViewSettings source={node} view={editing} schema={schema} door="full" onBack={() => setEditingId(null)} onClose={onClose} />
  ) : null

  // No minHeight floor — the list hugs its rows + footer (no dead space under the footer); ViewSettings
  // is naturally taller, and the slider animates between the two.
  return <PaneSlider active={editing ? 'b' : 'a'} slotA={list} slotB={detail} minWidth={225} />
}
