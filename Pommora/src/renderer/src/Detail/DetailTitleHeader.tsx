import { type Ref, useEffect, useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import './DetailTitleHeader.css'

/**
 * Shared detail-title chrome (Swift: DetailTitleHeader) — `[icon?] [name]` with a right-click →
 * Rename / Edit Icon menu; Rename flips the name to an inline editable field. The page editor
 * passes no icon (pages are title-only by design); the container/context banners pass theirs.
 */
interface Props {
  title: string
  /** The glyph to lead with — omitted renders title-only (the page editor's mode). Any Lucide id. */
  icon?: string
  /** Registers the icon glyph as the editable target — the picker's beak anchors to it. */
  iconRef?: Ref<SVGSVGElement>
  onRename: (newName: string) => void | Promise<boolean | void>
  /** Pops the native title menu and resolves the chosen action (Rename / Change Icon / Hide-Show Icon). */
  requestMenu: () => Promise<'rename' | 'editIcon' | 'toggleIcon' | null>
  onEditIcon: () => void
  /** Toggle the banner-heading icon's visibility (G-4). When absent, the menu omits the Hide/Show item. */
  onToggleIcon?: () => void
  /** The heading icon is hidden — it stays mounted but collapses/slides out (so hide/show animates). */
  iconHidden?: boolean
}

export function DetailTitleHeader({
  title,
  icon,
  iconRef,
  onRename,
  requestMenu,
  onEditIcon,
  onToggleIcon,
  iconHidden,
}: Props): React.JSX.Element {
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
    else if (action === 'toggleIcon') onToggleIcon?.()
  }

  return (
    // Only the icon glyph + the name text are Rename / Edit-Icon targets — not the full-width row.
    <div className="detail-title">
      {icon && (
        <Icon
          ref={iconRef}
          name={icon}
          className={iconHidden ? 'detail-title-icon is-hidden' : 'detail-title-icon'}
          onContextMenu={editing ? undefined : openMenu}
        />
      )}
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
