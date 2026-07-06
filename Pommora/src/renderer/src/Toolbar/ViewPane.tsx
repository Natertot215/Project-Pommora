import { type ReactNode, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { mintDefaultView, mintNewView, type SavedView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { Menu, MenuItem, MenuBottomRow, MenuScrollFrame, AccessoryButton } from '../design-system/components/menu'
import { PaneSlider } from '../Components/Detail/PaneSlider'
import { ViewSettings } from '../Components/Detail/ViewSettings'
import { PaneDnd, RowShell, usePaneRegions } from '../Components/Detail/paneDnd'
import { type PaneDrop, type PaneRow, paneSlot } from '../Components/Detail/paneDndModel'
import { saveViewAdopting } from '../Detail/Views/viewMint'
import { EditableInput } from '../Components/EditableInput'
import { IconPicker } from '../Components/IconPicker'
import { useSession } from '../store'
import * as vd from './viewDropdown.css'

// ── KNOB — the pane opens at least this square (width floor × the same as height floor). A sparse list
// reserves the square with its footer pinned to the bottom; view rows fill the reserved space top-down
// and only grow the pane once they'd exceed it. Tune the square edge here. ──
const PANE_SQUARE = 225

// The view list is one flat reorderable list — no assign/hide zones, so every drop is a reorder within
// it. Region-agnostic (the engine's snapshot still needs both region rects, but this ignores them): the
// row mids alone pick the insertion index, in the without-dragged coordinates `views:reorder` splices at.
const viewSlot: typeof paneSlot = (rows, _byId, _regions, pointerY, draggedId) => {
  const others = rows.filter((r) => r.id !== draggedId)
  let i = 0
  while (i < others.length && pointerY >= others[i].mid) i++
  const last = others[others.length - 1]
  const lineY = i < others.length ? others[i].top : last ? last.bottom : null
  return { drop: { kind: 'reorder-assigned', propId: draggedId, toIndex: i }, lineY, highlightAll: false }
}

/** Registers the drag region on the rows container. A pure reorder has no assign/hide zones, so both of
 *  the engine's region refs ride the one element — its snapshot needs both non-null; `viewSlot` ignores
 *  their rects. */
function DragRegion({ children }: { children: ReactNode }): React.JSX.Element {
  const { assignedRef, allRef } = usePaneRegions()
  const region = (el: HTMLElement | null): void => {
    assignedRef(el)
    allRef(el)
  }
  return (
    <div ref={region} data-group="assigned">
      {children}
    </div>
  )
}

/**
 * The ViewPane — the navigation dropdown the ViewDropdown discloses. A row per saved view (click
 * switches the active view + closes; the chevron pushes into ViewSettings; drag reorders; right-click
 * opens Rename / Edit Icon / Delete) over a footer BottomRow (+ create · … more), the two levels riding
 * one PaneSlider.
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
  const [renamingId, setRenamingId] = useState<string | null>(null)
  const [iconOpen, setIconOpen] = useState(false)
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

  const paneRows: PaneRow[] = rows.map((v) => ({ id: v.id, group: 'assigned' as const }))
  const nameFor = (id: string): string => rows.find((v) => v.id === id)?.name ?? ''
  const onDrop = (drop: PaneDrop): void => {
    if (drop.kind !== 'reorder-assigned' || views.length < 2) return
    const order = rows.map((v) => v.id).filter((id) => id !== drop.propId)
    order.splice(drop.toIndex, 0, drop.propId)
    void (async () => {
      const res = await window.nexus.views.reorder(node.path, node.kind, order)
      if (!res.ok) return void window.nexus.showError(res.error)
      await load()
    })()
  }

  const commitRename = (v: SavedView, next: string): void => {
    setRenamingId(null)
    if (next && next !== v.name) void saveViewAdopting(node, { ...v, name: next }, load)
  }
  const rowMenu = async (v: SavedView, e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.viewRowMenu(views.length > 1)
    if (action === 'view:rename') setRenamingId(v.id)
    else if (action === 'view:edit-icon') setIconOpen(true)
    else if (action === 'view:delete') {
      const res = await window.nexus.views.delete(node.path, node.kind, v.id)
      if (!res.ok) return void window.nexus.showError(res.error)
      await load()
    }
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
      <PaneDnd rows={paneRows} labelFor={nameFor} onDrop={onDrop} slot={viewSlot}>
        <DragRegion>
          <Menu>
            {rows.map((v) => (
              <RowShell key={v.id} id={v.id}>
                <MenuItem
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
                  onClick={renamingId === v.id ? undefined : () => void switchTo(v.id)}
                  onContextMenu={(e) => void rowMenu(v, e)}
                >
                  {renamingId === v.id ? (
                    <EditableInput
                      value={v.name}
                      className="row-title-input"
                      caretAtEnd
                      onCommit={(next) => commitRename(v, next)}
                      onCancel={() => setRenamingId(null)}
                    />
                  ) : (
                    v.name
                  )}
                </MenuItem>
              </RowShell>
            ))}
          </Menu>
        </DragRegion>
      </PaneDnd>
    </MenuScrollFrame>
  )

  const detail = editing ? (
    <ViewSettings source={node} view={editing} schema={schema} door="full" onBack={() => setEditingId(null)} onClose={onClose} />
  ) : null

  // The pane reserves a square (PANE_SQUARE via the slider's floors) so a sparse list doesn't collapse;
  // the list's MenuScrollFrame fills it, pins the +/… footer at the bottom, and scrolls the rows once
  // they'd exceed its ceiling. The slider only slides + resizes between the list and ViewSettings.
  return (
    <>
      <PaneSlider open={!!editing} root={list} detail={detail} minWidth={PANE_SQUARE} minHeight={PANE_SQUARE} />
      <IconPicker open={iconOpen} onClose={() => setIconOpen(false)} />
    </>
  )
}
