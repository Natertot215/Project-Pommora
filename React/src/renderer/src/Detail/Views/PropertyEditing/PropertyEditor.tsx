import { useRef, useState } from 'react'

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
  onCommit,
  onCancel
}: {
  initial: string
  numeric?: boolean
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
  return (
    <input
      className="property-editor"
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
