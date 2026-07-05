import { useRef } from 'react'
import { Icon, defaultEntityIcon } from '@renderer/design-system/symbols'
import { GlassControls } from '@renderer/design-system/materials'
import { dropdownOpen, dropdownClose } from '@renderer/design-system/animations.css'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import type { ConnPage } from './connections'

interface Props {
  /** Whether the autocomplete is active; false plays the retract before unmounting. */
  open: boolean
  candidates: ConnPage[]
  index: number
  left: number
  top: number
  query: string
  onPick: (page: ConnPage) => void
}

export function AutocompletePanel({ open, candidates, index, left, top, query, onPick }: Props): React.JSX.Element | null {
  const live = open && candidates.length > 0
  const { mounted, closing } = useExitPresence(live)
  // Retain the last open state so the panel can retract in place after `ac` clears (position + rows gone).
  const last = useRef({ candidates, index, left, top, query })
  if (live) last.current = { candidates, index, left, top, query }
  if (!mounted) return null

  const v = last.current
  const matchLen = v.query.length
  return (
    <GlassControls
      className={`${closing ? dropdownClose : dropdownOpen} mdpm-ac`}
      style={
        {
          left: v.left,
          top: v.top,
          '--dropdown-origin': 'top left',
          ...(closing ? { pointerEvents: 'none' } : null)
        } as React.CSSProperties
      }
    >
      {v.candidates.map((p, i) => (
        <div
          key={p.id}
          className={`mdpm-ac-row${i === v.index ? ' mdpm-ac-selected' : ''}`}
          onMouseDown={(e) => {
            e.preventDefault()
            onPick(p)
          }}
        >
          <Icon name={defaultEntityIcon('page')} size={14} className="mdpm-ac-icon" />
          <span className="mdpm-ac-title">
            <span className="mdpm-ac-match">{p.title.slice(0, matchLen)}</span>
            {p.title.slice(matchLen)}
          </span>
        </div>
      ))}
    </GlassControls>
  )
}
