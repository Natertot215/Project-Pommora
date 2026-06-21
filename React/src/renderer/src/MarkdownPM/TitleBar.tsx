import { forwardRef, useRef, useState } from 'react'

interface Props {
  /** The page title (= filename, no `title` field). The editor remounts per page, so this is the seed. */
  title: string
  /** Commit a rename of the underlying `.md`. Resolves `false` if the rename failed, so the draft reverts. */
  onRename?: (newName: string) => void | Promise<boolean>
  /** Move focus into the body after an Enter-commit. */
  onCommit?: () => void
}

/** The inline page title above the body — filename = title, edited in place. Enter (or blur)
 *  commits a file rename (reverting if it fails); Escape reverts. Lives in the editor's reserved
 *  top zone and scroll-tracks with the body (the host translates it). */
export const TitleBar = forwardRef<HTMLDivElement, Props>(function TitleBar({ title, onRename, onCommit }, ref) {
  const [value, setValue] = useState(title)
  const reverting = useRef(false) // Escape sets this so the blur it triggers doesn't commit

  const commit = async (): Promise<void> => {
    const next = value.trim()
    if (!next || next === title) {
      setValue(title) // empty or unchanged → revert
      return
    }
    const ok = await onRename?.(next)
    if (ok === false) setValue(title) // rename rejected → restore the on-screen title
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
            e.currentTarget.blur() // commits once via onBlur
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
