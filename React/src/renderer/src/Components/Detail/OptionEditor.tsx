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
 * (Planning 7-3, Phase 2). Options render as squared `label`-shape chips; Status layers its three
 * groups on top of this same list (Phase 3). The caller owns persistence: `onSetOptions` writes the
 * whole array back through `property.setOptions` (+ error surface + reload).
 */
export function OptionEditor({
  type,
  options,
  onSetOptions
}: {
  type: PropertyType
  options: Option[]
  onSetOptions: (next: Option[]) => void
}): React.JSX.Element {
  const [adding, setAdding] = useState(false)

  const commitAdd = (raw: string): void => {
    setAdding(false)
    onSetOptions(addOption(options, raw.trim() || fallbackTitle(type)))
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
          <div key={o.value} className={s.optionRow}>
            <Chip shape="label" color={chipColorFor(o.color)} label={o.label} />
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
