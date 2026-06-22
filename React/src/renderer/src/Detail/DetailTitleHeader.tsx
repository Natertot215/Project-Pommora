import { useEffect, useRef, useState } from 'react'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import './DetailTitleHeader.css'

/**
 * Shared detail-title chrome (Swift: DetailTitleHeader) — `[icon] [name]` shown as text, with a
 * right-click → Rename / Edit Icon menu. Rename flips the name to an inline editable field. Used by
 * every banner-bearing view (the page editor + the container/context/homepage banners).
 */
interface Props {
  title: string
  /** The entity's assigned icon, if any — omitted/undefined renders no icon (empty). */
  icon?: IconName
  onRename: (newName: string) => void | Promise<boolean | void>
  /** Pops the native Rename / Edit Icon menu and resolves the chosen action. */
  requestMenu: () => Promise<'rename' | 'editIcon' | null>
  onEditIcon: () => void
}

export function DetailTitleHeader({ title, icon, onRename, requestMenu, onEditIcon }: Props): React.JSX.Element {
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
    // Only the icon glyph + the name text are Rename / Edit-Icon targets — not the full-width row.
    <div className="detail-title">
      {icon && <Icon name={icon} className="detail-title-icon" onContextMenu={editing ? undefined : openMenu} />}
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
