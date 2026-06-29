import { Icon } from '@renderer/design-system/symbols'
import { GlassControls } from '@renderer/design-system/materials'
import { dropdownMenu } from '@renderer/design-system/animations.css'
import type { ConnPage } from './connections'

interface Props {
  candidates: ConnPage[]
  index: number
  left: number
  top: number
  query: string
  onPick: (page: ConnPage) => void
}

export function AutocompletePanel({ candidates, index, left, top, query, onPick }: Props): React.JSX.Element | null {
  if (candidates.length === 0) return null
  const matchLen = query.length
  return (
    <GlassControls
      className={`${dropdownMenu} mdpm-ac`}
      style={{ left, top, '--dropdown-origin': 'top left' } as React.CSSProperties}
    >
      {candidates.map((p, i) => (
        <div
          key={p.id}
          className={`mdpm-ac-row${i === index ? ' mdpm-ac-selected' : ''}`}
          onMouseDown={(e) => {
            e.preventDefault()
            onPick(p)
          }}
        >
          <Icon name="file-text" size={14} className="mdpm-ac-icon" />
          <span className="mdpm-ac-title">
            <span className="mdpm-ac-match">{p.title.slice(0, matchLen)}</span>
            {p.title.slice(matchLen)}
          </span>
        </div>
      ))}
    </GlassControls>
  )
}
