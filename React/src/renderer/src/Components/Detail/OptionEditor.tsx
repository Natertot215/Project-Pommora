import { useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { chipLabel, chipColor } from '@renderer/design-system/tokens'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { addOption, fallbackTitle, type Option } from '@shared/optionModel'
import type { PropertyType } from '@shared/properties'
import { cx } from '@renderer/design-system/cx'
import { Chip } from '../Chip'
import { EditableInput } from '../EditableInput'
import * as s from './viewPane.css'

/**
 * The Select / Multi-Select option editor — the flat option list inside a property's editor pane
 * (Planning 7-3, Phase 2). Options render as squared `label`-shape chips; a right-click chip menu
 * (native) drives Rename (inline) · Remove · Clear. The caller owns persistence: each callback maps
 * to a `property.*Option` write (+ error surface + reload). Status layers grouping on top (Phase 3).
 */
export function OptionEditor({
  type,
  options,
  onSetOptions,
  onRenameOption,
  onRemoveOption,
  onClearOption
}: {
  type: PropertyType
  options: Option[]
  onSetOptions: (next: Option[]) => void
  onRenameOption: (oldValue: string, newTitle: string) => void
  onRemoveOption: (value: string) => void
  onClearOption: (value: string) => void
}): React.JSX.Element {
  const [adding, setAdding] = useState(false)
  const [renaming, setRenaming] = useState<string | null>(null)

  const commitAdd = (raw: string): void => {
    setAdding(false)
    onSetOptions(addOption(options, raw.trim() || fallbackTitle(type)))
  }
  const commitRename = (oldValue: string, raw: string): void => {
    setRenaming(null)
    const title = raw.trim() || fallbackTitle(type)
    if (title !== oldValue) onRenameOption(oldValue, title)
  }
  const openMenu = async (o: Option): Promise<void> => {
    const action = await window.nexus.optionMenu({ name: o.label })
    if (action === 'option:rename') setRenaming(o.value)
    else if (action === 'option:remove') onRemoveOption(o.value)
    else if (action === 'option:clear') onClearOption(o.value)
  }

  return (
    <div className={s.optionEditor}>
      <div className={s.optionsRow}>
        <span className={s.optionsLabel}>Options</span>
        <button type="button" className={s.optionsAdd} aria-label="Add Option" onClick={() => setAdding(true)}>
          <Icon name="plus" size={s.ICON.optionsAdd} />
        </button>
      </div>
      <div className={s.optionList}>
        {options.map((o) => (
          <div
            key={o.value}
            className={s.optionRow}
            onContextMenu={(e) => {
              e.preventDefault()
              void openMenu(o)
            }}
          >
            {renaming === o.value ? (
              <span className={cx(chipLabel, chipColor[chipColorFor(o.color)])}>
                <EditableInput
                  value={o.label}
                  autoSize
                  className={s.optionInput}
                  onCommit={(raw) => commitRename(o.value, raw)}
                  onCancel={() => setRenaming(null)}
                />
              </span>
            ) : (
              <Chip shape="label" color={chipColorFor(o.color)} label={o.label} />
            )}
          </div>
        ))}
        {adding ? (
          <div className={s.optionRow}>
            <span className={cx(chipLabel, chipColor.grey)}>
              <EditableInput value="" autoSize className={s.optionInput} onCommit={commitAdd} onCancel={() => setAdding(false)} />
            </span>
          </div>
        ) : null}
      </div>
    </div>
  )
}
