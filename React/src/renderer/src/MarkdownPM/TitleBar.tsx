import { forwardRef, useState } from 'react'

interface Props {
  /** The page title (= filename, no `title` field). The editor remounts per page, so this is the seed. */
  title: string
  /** Commit a rename of the underlying `.md` (host wires this to the existing rename op). */
  onRename?: (newName: string) => void
  /** Move focus into the body after an Enter-commit. */
  onCommit?: () => void
}

/**
 * The inline page title above the body — filename = title, edited in place. Enter (or blur) commits
 * a file rename; Escape reverts. It lives in the editor's reserved top zone and scroll-tracks with
 * the body (the host translates it). A hairline divider runs the text column beneath it. (Swift:
 * PageEditorView title field + separator.)
 */
export const TitleBar = forwardRef<HTMLDivElement, Props>(function TitleBar({ title, onRename, onCommit }, ref) {
  const [value, setValue] = useState(title)

  const commit = (): void => {
    const next = value.trim()
    if (next && next !== title) onRename?.(next)
    else setValue(title) // empty or unchanged → revert the draft
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
            commit()
            onCommit?.()
          } else if (e.key === 'Escape') {
            setValue(title)
            e.currentTarget.blur()
          }
        }}
        onBlur={commit}
      />
      <div className="mdpm-divider" />
    </div>
  )
})
