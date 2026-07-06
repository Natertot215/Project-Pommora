import { useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { chipPill, chipColor } from '@renderer/design-system/tokens'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { DROP_LINE_INSET } from '@renderer/design-system/interactions/shared'
import { addStatusOption, recolorStatusOption, relabelStatusGroup, moveStatusOption, fallbackTitle } from '@shared/optionModel'
import type { StatusGroup } from '@shared/properties'
import { cx } from '@renderer/design-system/cx'
import { Chip, chipShapeForType } from '../Chip'
import { EditableInput } from '../EditableInput'
import { ColorPicker } from './ColorPicker'
import { useStatusReorder } from './useStatusReorder'
import * as s from './settingsPane.css'

/**
 * The Status option editor (Planning 7-3) — the option list grouped by status group (Open / Active /
 * Done): each group's heading (double-click to rename its label; the calendar-locked id stays) + its
 * option chips (pills, the exclusive status shape), defaulting to the group's colour. The per-group +
 * reveals on group hover and adds an inline-named option; a hover palette icon opens the shared
 * ColorPicker (same placement + logic as the Select/Multi editor); dragging a chip reorders it within
 * its group or across into another (including an empty one). A right-click Rename/Remove/Clear menu
 * (native) mirrors the Select editor — Rename is inline, Remove/Clear cascade pages. The Style picker
 * lands in a later slice; registry-only edits ride setStatusGroups, the page-touching ops their own IPC.
 */
export function StatusEditor({
  groups,
  onSetGroups,
  onRenameOption,
  onRemoveOption,
  onClearOption
}: {
  groups: StatusGroup[]
  onSetGroups: (next: StatusGroup[]) => void
  onRenameOption: (oldValue: string, newTitle: string) => void
  onRemoveOption: (value: string) => void
  onClearOption: (value: string) => void
}): React.JSX.Element {
  const [adding, setAdding] = useState<string | null>(null) // the group id being added to
  const [renamingGroup, setRenamingGroup] = useState<string | null>(null) // the group id being relabeled
  const [renaming, setRenaming] = useState<string | null>(null) // the option value being renamed
  const [coloring, setColoring] = useState<string | null>(null) // the option value being recolored
  const paletteBtnRef = useRef<HTMLButtonElement>(null)
  const reorder = useStatusReorder(
    groups.map((g) => ({ id: g.id, values: g.options.map((o) => o.value) })),
    (value, toGroupId, toIndex) => onSetGroups(moveStatusOption(groups, value, toGroupId, toIndex))
  )

  const commitAdd = (groupId: string, raw: string): void => {
    setAdding(null)
    const g = groups.find((x) => x.id === groupId)
    onSetGroups(addStatusOption(groups, groupId, raw.trim() || fallbackTitle('status', g?.label)))
  }
  const commitGroupRename = (groupId: string, raw: string): void => {
    setRenamingGroup(null)
    const title = raw.trim()
    if (title) onSetGroups(relabelStatusGroup(groups, groupId, title))
  }
  const commitRename = (oldValue: string, raw: string, groupLabel: string): void => {
    setRenaming(null)
    const title = raw.trim() || fallbackTitle('status', groupLabel)
    if (title !== oldValue) onRenameOption(oldValue, title)
  }
  const openMenu = async (value: string, name: string): Promise<void> => {
    const action = await window.nexus.optionMenu({ name })
    if (action === 'option:rename') setRenaming(value)
    else if (action === 'option:remove') onRemoveOption(value)
    else if (action === 'option:clear') onClearOption(value)
  }
  const pickColor = (value: string, color: string | undefined): void => {
    setColoring(null)
    onSetGroups(recolorStatusOption(groups, value, color))
  }

  return (
    <div className={s.statusGroups}>
      {groups.map((g) => (
        <div key={g.id} className={s.statusGroup}>
          <div className={s.optionsRow}>
            {renamingGroup === g.id ? (
              <span className={s.optionsLabel}>
                <EditableInput
                  value={g.label}
                  autoSize
                  className={s.optionInput}
                  onCommit={(raw) => commitGroupRename(g.id, raw)}
                  onCancel={() => setRenamingGroup(null)}
                />
              </span>
            ) : (
              <span className={s.optionsLabel} onDoubleClick={() => setRenamingGroup(g.id)}>
                {g.label}
              </span>
            )}
            <button type="button" className={s.groupAdd} aria-label={`Add to ${g.label}`} onClick={() => setAdding(g.id)}>
              <Icon name="plus" size={s.ICON.optionsAdd} />
            </button>
          </div>
          <div className={s.optionList} ref={(el) => reorder.registerGroup(g.id, el)}>
            {g.options.map((o) => {
              const isColoring = coloring === o.value
              return (
                <div
                  key={o.value}
                  ref={(el) => reorder.registerRow(o.value, el)}
                  className={cx(s.optionRow, reorder.dragging === o.value && s.rowDragging)}
                  onPointerDown={(e) => reorder.onRowPointerDown(o.value, e)}
                  onContextMenu={(e) => {
                    e.preventDefault()
                    void openMenu(o.value, o.label)
                  }}
                >
                  {renaming === o.value ? (
                    <span className={cx(chipPill, chipColor[chipColorFor(o.color ?? g.color)])}>
                      <EditableInput
                        value={o.label}
                        autoSize
                        className={s.optionInput}
                        onCommit={(raw) => commitRename(o.value, raw, g.label)}
                        onCancel={() => setRenaming(null)}
                      />
                    </span>
                  ) : (
                    <>
                      <Chip shape={chipShapeForType('status')} color={chipColorFor(o.color ?? g.color)} label={o.label} />
                      <span className={s.paletteAnchor}>
                        <button
                          ref={isColoring ? paletteBtnRef : undefined}
                          type="button"
                          className={s.paletteButton}
                          style={isColoring ? { opacity: 1 } : undefined}
                          aria-label="Recolor"
                          onClick={() => setColoring((v) => (v === o.value ? null : o.value))}
                        >
                          <Icon name="palette" size={s.ICON.palette} />
                        </button>
                        <ColorPicker
                          open={isColoring}
                          selected={chipColorFor(o.color ?? g.color)}
                          onPick={(color) => pickColor(o.value, color)}
                          onDismiss={() => setColoring(null)}
                          triggerRef={paletteBtnRef}
                        />
                      </span>
                    </>
                  )}
                </div>
              )
            })}
            {adding === g.id ? (
              <div className={s.optionRow}>
                <span className={cx(chipPill, chipColor[chipColorFor(g.color)])}>
                  <EditableInput
                    value=""
                    autoSize
                    className={s.optionInput}
                    onCommit={(raw) => commitAdd(g.id, raw)}
                    onCancel={() => setAdding(null)}
                  />
                </span>
              </div>
            ) : null}
            {reorder.drop?.groupId === g.id ? (
              <div className="table-drop-line" aria-hidden style={{ top: reorder.drop.top, left: DROP_LINE_INSET, right: DROP_LINE_INSET }}>
                <span className="table-drop-dot" />
              </div>
            ) : null}
          </div>
        </div>
      ))}
    </div>
  )
}
