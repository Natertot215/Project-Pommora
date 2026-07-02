import { useEffect, useRef, useState } from 'react'
import './DetailTitleHeader.css'

/**
 * Shared detail-title chrome (Swift: DetailTitleHeader) — the page editor's title-only header
 * (pages never show an icon here, by design — bannered container/context views carry theirs in
 * the Banner), with a right-click → Rename / Edit Icon menu. Rename flips the name to an inline
 * editable field.
 */
interface Props {
  title: string
  onRename: (newName: string) => void | Promise<boolean | void>
  /** Pops the native Rename / Edit Icon menu and resolves the chosen action. */
  requestMenu: () => Promise<'rename' | 'editIcon' | null>
  onEditIcon: () => void
}

export function DetailTitleHeader({ title, onRename, requestMenu, onEditIcon }: Props): React.JSX.Element {
  const [editing, setEditing] = useState(false)
  const [value, setValue] = useState(title)
  const reverting = useRef(false) // Escape sets this so the blur it triggers doesn't commit
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => setValue(title), [title])
  useEffect(() => {
    if (editing) {
      inputRef.current?.focus()
      inputRef.current?.select()
    }
  }, [editing])

  const commit = async (): Promise<void> => {
    setEditing(false)
    const next = value.trim()
    if (!next || next === title) {
      setValue(title)
      return
    }
    const res = await onRename(next)
    if (res === false) setValue(title)
  }

  const openMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation() // don't also trip the banner's Change/Remove menu underneath
    const action = await requestMenu()
    if (action === 'rename') setEditing(true)
    else if (action === 'editIcon') onEditIcon()
  }

  return (
    // Only the name text is the Rename / Edit-Icon target — not the full-width row.
    <div className="detail-title">
      {editing ? (
        <input
          ref={inputRef}
          className="detail-title-input"
          value={value}
          spellCheck={false}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              void commit()
            } else if (e.key === 'Escape') {
              reverting.current = true
              setValue(title)
              setEditing(false)
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
      ) : (
        <span className="detail-title-text" onContextMenu={openMenu}>
          {title}
        </span>
      )}
    </div>
  )
}
