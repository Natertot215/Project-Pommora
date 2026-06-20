import { useRef } from 'react'

/**
 * Shared inline-edit input: autofocus + select-all, commit on Enter/blur, cancel on Escape.
 * The `settled` guard stops Enter (which blurs) and the trailing blur from both committing;
 * it's mounted only while editing, so each edit session gets a fresh guard. Consumers own
 * the commit/cancel meaning — store dispatch for sidebar rows, local callbacks for the header.
 */
export function EditableInput({
  value,
  className,
  maxLength,
  onCommit,
  onCancel
}: {
  value: string
  className: string
  maxLength?: number
  onCommit: (next: string) => void
  onCancel: () => void
}): React.JSX.Element {
  const settled = useRef(false)
  return (
    <input
      className={className}
      defaultValue={value}
      autoFocus
      maxLength={maxLength}
      onFocus={(e) => e.currentTarget.select()}
      onClick={(e) => e.stopPropagation()}
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
}
