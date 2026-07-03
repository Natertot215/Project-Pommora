import { useRef } from 'react'
import { cx } from '../design-system/cx'
import { autoSizeWrap, autoSizeMirror, autoSizeInput } from './EditableInput.css'

/**
 * Shared inline-edit input: autofocus + select-all, commit on Enter/blur, cancel on Escape.
 * The `settled` guard stops Enter (which blurs) and the trailing blur from both committing;
 * it's mounted only while editing, so each edit session gets a fresh guard. Consumers own
 * the commit/cancel meaning — store dispatch for sidebar rows, local callbacks for the header.
 *
 * `autoSize` shrink-wraps the field to its text via a hidden mirror span (the option-chip caret);
 * font + padding inherit from the caller's surface so the mirror measures in the same metrics.
 */
export function EditableInput({
  value,
  className,
  maxLength,
  autoSize,
  onCommit,
  onCancel
}: {
  value: string
  className: string
  maxLength?: number
  autoSize?: boolean
  onCommit: (next: string) => void
  onCancel: () => void
}): React.JSX.Element {
  const settled = useRef(false)
  const mirror = useRef<HTMLSpanElement>(null)
  const field = (
    <input
      className={cx(className, autoSize && autoSizeInput)}
      defaultValue={value}
      autoFocus
      size={autoSize ? 1 : undefined}
      maxLength={maxLength}
      onFocus={(e) => e.currentTarget.select()}
      onClick={(e) => e.stopPropagation()}
      onInput={autoSize ? (e) => {
        if (mirror.current) mirror.current.textContent = e.currentTarget.value || ' '
      } : undefined}
      onKeyDown={(e) => {
        if (e.key === 'Enter') e.currentTarget.blur()
        else if (e.key === 'Escape') {
          settled.current = true
          onCancel()
        }
      }}
      onBlur={(e) => {
        if (settled.current) return
        settled.current = true
        onCommit(e.currentTarget.value.trim())
      }}
    />
  )
  if (!autoSize) return field
  return (
    <span className={autoSizeWrap}>
      <span ref={mirror} className={autoSizeMirror} aria-hidden>
        {value || ' '}
      </span>
      {field}
    </span>
  )
}
