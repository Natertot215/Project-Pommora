import { useEffect, useRef, useState } from 'react'
import { cx } from '@renderer/design-system/cx'

/**
 * The inline text editor every container view's cells share (A-12: Enter = confirm ·
 * click-out = save · Esc = revert and exit). Table-agnostic: raw text in/out — the caller
 * owns the value typing, parsing, and write. `numeric` filters keystrokes so an invalid
 * number can never be typed (Nathan, at pickup). The done-guard keeps Enter's commit from
 * double-firing through the blur that follows it.
 */
export function PropertyEditor({
  initial,
  numeric = false,
  validate,
  color,
  onCommit,
  onCancel,
}: {
  initial: string
  numeric?: boolean
  /** When set, non-empty text that fails it renders ghosted (faded to --state-ghost) — a live "not a
   *  valid value yet" cue for the url field, which commits nothing until it passes. */
  validate?: (raw: string) => boolean
  /** Overrides the field's text colour — the url field wears its link colour, so typing previews as the
   *  link (ghosted until valid, then solid). */
  color?: string
  onCommit: (raw: string) => void
  onCancel: () => void
}): React.JSX.Element {
  const [text, setText] = useState(initial)
  const done = useRef(false)
  const finish = (fn: () => void): void => {
    if (done.current) return
    done.current = true
    fn()
  }
  // A non-blur teardown (keyboard navigation, programmatic switch) must not drop typed text —
  // flush on unmount. Changed-text guard keeps StrictMode's dev cleanup cycle from committing
  // the untouched initial value.
  const textRef = useRef(text)
  textRef.current = text
  const commitRef = useRef(onCommit)
  commitRef.current = onCommit
  useEffect(
    () => () => {
      if (!done.current && textRef.current !== initial)
        finish(() => commitRef.current(textRef.current))
    },
    // biome-ignore lint/correctness/useExhaustiveDependencies: unmount-only flush; refs carry the latest.
    [],
  )
  return (
    <input
      className={cx(
        'property-editor',
        validate != null && text.trim() !== '' && !validate(text.trim()) && 'property-editor-ghost',
      )}
      style={color ? { color } : undefined}
      autoFocus
      value={text}
      onChange={(e) => {
        const next = e.target.value
        if (numeric && !/^-?\d*(\.\d*)?$/.test(next)) return
        setText(next)
      }}
      onKeyDown={(e) => {
        e.stopPropagation()
        if (e.key === 'Enter') finish(() => onCommit(text))
        else if (e.key === 'Escape') finish(onCancel)
      }}
      onBlur={() => finish(() => onCommit(text))}
      onClick={(e) => e.stopPropagation()}
    />
  )
}
