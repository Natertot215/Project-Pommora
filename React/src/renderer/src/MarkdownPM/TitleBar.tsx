import { forwardRef, useRef, useState } from 'react'

interface Props {
  title: string
  onRename?: (newName: string) => void | Promise<boolean>
  onCommit?: () => void
}

export const TitleBar = forwardRef<HTMLDivElement, Props>(function TitleBar({ title, onRename, onCommit }, ref) {
  const [value, setValue] = useState(title)
  const reverting = useRef(false) // Escape sets this so the blur it triggers doesn't commit

  const commit = async (): Promise<void> => {
    const next = value.trim()
    if (!next || next === title) {
      setValue(title)
      return
    }
    const ok = await onRename?.(next)
    if (ok === false) setValue(title)
  }

  return (
    <div className="mdpm-titlebar" ref={ref}>
      <input
        className="mdpm-title"
        value={value}
        placeholder="Untitled"
        spellCheck={false}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault()
            e.currentTarget.blur()
            onCommit?.()
          } else if (e.key === 'Escape') {
            reverting.current = true
            setValue(title)
            e.currentTarget.blur()
          }
        }}
        onBlur={() => {
          if (reverting.current) {
            reverting.current = false
            return
          }
          void commit()
        }}
      />
      <div className="mdpm-divider" />
    </div>
  )
})
