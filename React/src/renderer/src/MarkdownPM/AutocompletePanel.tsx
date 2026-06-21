import { Icon } from '@renderer/design-system/symbols'
import type { ConnPage } from './connections'

interface Props {
  candidates: ConnPage[]
  index: number
  /** Caret viewport coords (the panel anchors just below). */
  left: number
  top: number
  /** The typed query — its prefix length is rendered emphasised in each title. */
  query: string
  onPick: (page: ConnPage) => void
}

/** The `[[` autocomplete: a caret-anchored list of pages, prefix of each title emphasised. Keyboard
 *  nav + accept are handled in the editor (this only paints + supports click). */
export function AutocompletePanel({ candidates, index, left, top, query, onPick }: Props): React.JSX.Element | null {
  if (candidates.length === 0) return null
  const matchLen = query.length
  return (
    <div className="mdpm-ac" style={{ left, top }}>
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
    </div>
  )
}
