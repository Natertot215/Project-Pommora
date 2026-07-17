import { useEffect, useRef } from 'react'
import { cx } from '../design-system/cx'
import { autoSizeWrap, autoSizeMirror, autoSizeInput } from './EditableInput.css'

/**
 * Shared inline-edit input: autofocus (select-all, or drop the caret at the end via `caretAtEnd`),
 * commit on Enter/blur, cancel on Escape.
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
  caretAtEnd,
  onCommit,
  onCancel,
}: {
  value: string
  className: string
  maxLength?: number
  autoSize?: boolean
  /** Focus drops the caret at the END of the text instead of selecting all — for editing in place (the
   *  rename field) rather than replacing. Default selects all (type-to-replace: the chip/sidebar rename). */
  caretAtEnd?: boolean
  onCommit: (next: string) => void
  onCancel: () => void
}): React.JSX.Element {
  const settled = useRef(false)
  const mirror = useRef<HTMLSpanElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  // Focus so an active caret blinks the moment the field appears. Mounted already-visible (the sidebar /
  // chip rename) it takes focus at once; mounted inside PickerMenu's rename pane it can't yet — the pane
  // is visibility:hidden until measured, and it's launched from a native menu whose focus-return is
  // async — so a short backstop re-asserts once it's shown. Re-focusing a focused field is a no-op.
  useEffect(() => {
    const el = inputRef.current
    if (!el) return
    el.focus()
    const t = setTimeout(() => el.focus(), 60)
    return () => clearTimeout(t)
  }, [])
  const field = (
    <input
      ref={inputRef}
      className={cx(className, autoSize && autoSizeInput)}
      defaultValue={value}
      size={autoSize ? 1 : undefined}
      maxLength={maxLength}
      onFocus={(e) => {
        if (!caretAtEnd) return e.currentTarget.select()
        const len = e.currentTarget.value.length
        e.currentTarget.setSelectionRange(len, len)
      }}
      onClick={(e) => e.stopPropagation()}
      onInput={
        autoSize
          ? (e) => {
              if (mirror.current) mirror.current.textContent = e.currentTarget.value || ' '
            }
          : undefined
      }
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
