import { useEffect, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { mintDefaultView, mintNewView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { Menu, MenuItem, MenuBottomRow, AccessoryButton, MENU_MAX_HEIGHT } from '../design-system/components/menu'
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
  // `active` lags `editingId` by a frame on push: the detail mounts (slot B) first so the slider measures
  // its height, THEN we flip — the viewport animates open to a known height instead of snapping from
  // `auto` (the entry bounce). Back flips immediately so the slide-out isn't delayed.
  const [active, setActive] = useState<'a' | 'b'>('a')
  useEffect(() => {
    if (!editingId) {
      setActive('a')
      return
    }
    const raf = requestAnimationFrame(() => setActive('b'))
    return () => cancelAnimationFrame(raf)
  }, [editingId])
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
    <Menu className={vd.paneMenu}>
      <div className={vd.rowsFill}>
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
      </div>
      <MenuBottomRow
        leading={<AccessoryButton icon="plus" size={12} box={20} ariaLabel="New View" onClick={() => void createView()} />}
        trailing={<AccessoryButton icon="dots" size={12} box={20} ariaLabel="More" onClick={() => {}} />}
      />
    </Menu>
  )

  const detail = editing ? (
    <ViewSettings source={node} view={editing} schema={schema} door="full" onBack={() => setEditingId(null)} onClose={onClose} />
  ) : null

  // The pane reserves a square (PANE_SQUARE) so a sparse list doesn't collapse — rows fill it top-down
  // with the footer pinned to the bottom (vd.rowsFill), and only past the square does it grow. The
  // shared MENU_MAX_HEIGHT caps a long list / tall ViewSettings; past it the slot (or the leaf's own
  // MenuScrollFrame) scrolls instead of clipping.
  return (
    <PaneSlider
      active={active}
      slotA={list}
      slotB={detail}
      minWidth={PANE_SQUARE}
      minHeight={PANE_SQUARE}
      maxHeight={MENU_MAX_HEIGHT}
    />
  )
}
