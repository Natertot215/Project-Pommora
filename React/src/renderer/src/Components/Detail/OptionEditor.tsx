import { Icon } from '@renderer/design-system/symbols'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { Chip } from '../Chip'
import * as s from './viewPane.css'

type EditableOption = { value: string; label: string; color?: string }

/**
 * The Select / Multi-Select option editor — the flat option list inside a property's editor pane
 * (Planning 7-3, Phase 2). Options render as squared `label`-shape chips; Status layers its three
 * groups on top of this same list (Phase 3). Edits route through the caller's `property.*Option` IPC.
 */
export function OptionEditor({ options }: { options: EditableOption[] }): React.JSX.Element {
  return (
    <div className={s.optionEditor}>
      <div className={s.optionsRow}>
        <span className={s.optionsLabel}>Options</span>
        <button type="button" className={s.optionsAdd} aria-label="Add Option">
          <Icon name="plus" size={s.ICON.optionsAdd} />
        </button>
      </div>
      <div className={s.optionList}>
        {options.map((o) => (
          <div key={o.value} className={s.optionRow}>
            <Chip shape="label" color={chipColorFor(o.color)} label={o.label} />
          </div>
        ))}
      </div>
    </div>
  )
}
