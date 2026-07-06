import { useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { mintDefaultView, mintNewView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { Menu, MenuItem, MenuBottomRow, MenuScrollFrame, AccessoryButton } from '../design-system/components/menu'
import { PaneSlider } from '../Components/Detail/PaneSlider'
import { ViewSettings } from '../Components/Detail/ViewSettings'
import { useSession } from '../store'
import * as vd from './viewDropdown.css'

// ── KNOB — the pane opens at least this square (width floor × the same as height floor). A sparse list
// reserves the square with its footer pinned to the bottom; view rows fill the reserved space top-down
// and only grow the pane once they'd exceed it. Tune the square edge here. ──
const PANE_SQUARE = 225

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
  const [editingId, setEditingId] = useState<string | null>(null)
  const views = node.views ?? []
  // The list never renders empty: during the entry-mint beat (a legacy container's first open, before
  // the refetch lands) show the in-memory sentinel default, same as the button + table (G-4).
  const rows = views.length ? views : [mintDefaultView(schema)]
  // Re-derive the edited view from the live tree so an edit (rename/type/format) shows fresh, not a
  // stale snapshot; a gone id (deleted) collapses back to the list.
  const editing = editingId ? rows.find((v) => v.id === editingId) : undefined

  const switchTo = async (id: string): Promise<void> => {
    await setActiveView(node.id, id)
    onClose()
  }
  const createView = async (): Promise<void> => {
    await window.nexus.views.save(node.path, node.kind, mintNewView('Untitled', schema))
    await load()
  }

  const list = (
    <MenuScrollFrame
      footer={
        <MenuBottomRow
          leading={<AccessoryButton icon="plus" size={12} box={20} ariaLabel="New View" onClick={() => void createView()} />}
          trailing={<AccessoryButton icon="dots" size={12} box={20} ariaLabel="More" onClick={() => {}} />}
        />
      }
    >
      <Menu>
        {rows.map((v) => (
          <MenuItem
            key={v.id}
            leading={<Icon name={iconNameOr(v.icon, 'table')} size={16} />}
            trailing={
              <button
                type="button"
                className={vd.chevronButton}
                aria-label={`Edit ${v.name}`}
                onClick={(e) => {
                  e.stopPropagation()
                  setEditingId(v.id)
                }}
              >
                <Icon name="chevron-right" size={16} />
              </button>
            }
            onClick={() => void switchTo(v.id)}
          >
            {v.name}
          </MenuItem>
        ))}
      </Menu>
    </MenuScrollFrame>
  )

  const detail = editing ? (
    <ViewSettings source={node} view={editing} schema={schema} door="full" onBack={() => setEditingId(null)} onClose={onClose} />
  ) : null

  // The pane reserves a square (PANE_SQUARE via the slider's floors) so a sparse list doesn't collapse;
  // the list's MenuScrollFrame fills it, pins the +/… footer at the bottom, and scrolls the rows once
  // they'd exceed its ceiling. The slider only slides + resizes between the list and ViewSettings.
  return <PaneSlider open={!!editing} root={list} detail={detail} minWidth={PANE_SQUARE} minHeight={PANE_SQUARE} />
}
