import type { CSSProperties, RefObject } from 'react'
import { EditableInput } from '@renderer/Components/EditableInput'
import { cx } from '../../cx'
import { PickerMenu } from '../PickerMenu/PickerMenu'
import '../OverflowScroll.css'
import * as s from './textPicker.css'

/**
 * TextPicker — a beaked PickerMenu wrapping one input-field, for renaming/labelling a cell in place
 * (the link alias, to start). Self-managed like ColorPicker (`open`/`onDismiss`/`triggerRef`). The
 * field grows with typing between a 100px floor and a 200px cap, then scrolls; Enter or blur commit the
 * trimmed text, Escape cancels. `accent` scopes the pane's `--accent` so the focus stroke wears a
 * caller's colour (a link tints it its own); omitted, it inherits the app accent.
 */
export function TextPicker({
  open,
  onDismiss,
  triggerRef,
  value,
  onCommit,
  accent,
  maxLength,
  trailing
}: {
  open: boolean
  onDismiss: () => void
  triggerRef: RefObject<HTMLElement | null>
  value: string
  onCommit: (next: string) => void
  accent?: string
  maxLength?: number
  /** An optional right-side adornment on the field's line — a number's "/ N" out-of hint. */
  trailing?: React.ReactNode
}): React.JSX.Element | null {
  const hasTrailing = trailing !== undefined
  const field = (
    <EditableInput
      value={value}
      className={hasTrailing ? cx(s.suffixInput, 'overflow-eclipse') : s.input}
      maxLength={maxLength}
      caretAtEnd
      onCommit={onCommit}
      onCancel={onDismiss}
    />
  )
  return (
    <PickerMenu
      open={open}
      onDismiss={onDismiss}
      triggerRef={triggerRef}
      direction="down"
      center
      // Concentric with the input field: its 8px radius + the 4px gutter, so the gap reads uniform.
      radius={12}
      notchWidth={14}
      contentClassName={s.content}
      style={accent ? ({ '--accent': accent } as CSSProperties) : undefined}
    >
      {hasTrailing ? (
        <div className={s.suffixField}>
          {field}
          <span className={s.trailing}>{trailing}</span>
        </div>
      ) : (
        field
      )}
    </PickerMenu>
  )
}
