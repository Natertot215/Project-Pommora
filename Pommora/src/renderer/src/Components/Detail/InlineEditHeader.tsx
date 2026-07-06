import { useState } from 'react'
import { InteractionField, fieldInputClass } from '../../design-system/components/InteractionField'
import { EditableInput } from '../EditableInput'
import { DashIcon } from './DashIcon'
import * as s from './settingsPane.css'

/**
 * The icon-button + inline-rename title header shared by the ViewPane (Collection/Set) and the
 * property editor. Owns the editing toggle; the title commits on blur with no focus ring, and
 * `onCommit` fires only on a real change. The icon opens its picker via `onIconClick`.
 */
export function InlineEditHeader({
  value,
  onCommit,
  onIconClick
}: {
  value: string
  onCommit: (next: string) => void
  onIconClick: () => void
}): React.JSX.Element {
  const [editing, setEditing] = useState(false)
  return (
    <div className={s.header}>
      <button type="button" className={s.iconButton} aria-label="Edit icon" onClick={onIconClick}>
        <DashIcon />
      </button>
      {editing ? (
        <EditableInput
          value={value}
          className={`${fieldInputClass} ${s.titleField}`}
          onCommit={(next) => {
            setEditing(false)
            if (next && next !== value) onCommit(next)
          }}
          onCancel={() => setEditing(false)}
        />
      ) : (
        <InteractionField className={s.titleField} onClick={() => setEditing(true)}>
          {value}
        </InteractionField>
      )}
    </div>
  )
}
