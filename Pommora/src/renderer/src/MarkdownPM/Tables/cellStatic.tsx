import { tokenize } from '../tokens'
import { CONTENT_CLASS } from '../decorations/intent'
import { isValidLink } from '@shared/links'
import type { ConnectionsApi } from '../connections'

// A cell's resting render WITHOUT a CodeMirror instance: inline marks styled + markers hidden +
// connections coloured by status, matching the nested editor's look. Only the focused cell mounts a
// real editor (see TableView), so a table scrolling into view no longer builds R×C editors in one frame.
// Block-level markdown (headings, lists, fences) isn't reproduced here — it doesn't occur in a cell.
export function renderCellContent(text: string, getConn?: () => ConnectionsApi | undefined): React.ReactNode {
  // Fast path: no markdown-significant char → no token possible, so skip the mdast parse. Most cells are
  // plain text, and this is the per-cell cost paid when a table scrolls into view.
  if (!/[*_~`[$]/.test(text)) return text
  const tokens = tokenize(text)
  if (tokens.length === 0) return text
  const conn = getConn?.()
  const out: React.ReactNode[] = []
  let pos = 0
  let key = 0
  for (const tk of tokens) {
    const [s, e] = tk.range
    if (s < pos) continue // overlapping token already covered by an earlier one
    if (s > pos) out.push(text.slice(pos, s))
    const content = text.slice(tk.contentRange[0], tk.contentRange[1])
    if (tk.kind === 'wikiLink') {
      const status = conn?.resolve(content).status
      // Phantom (or no index) → raw `[[…]]` inert, exactly as the editor leaves it.
      if (!status || status === 'phantom') out.push(text.slice(s, e))
      else {
        out.push(<span key={key++} className={`md-connection-${status}`}>{content}</span>)
        // A piped `[[Title|alias]]` styles only the Title; the editor leaves `|alias` plain-visible, so match it.
        const aliasTail = text.slice(tk.contentRange[1], e - 2)
        if (aliasTail) out.push(aliasTail)
      }
    } else if (tk.kind === 'link') {
      const url = text.slice(tk.contentRange[1] + 2, e - 1)
      out.push(
        <span key={key++} className={isValidLink(url) ? 'md-link' : 'md-link-invalid'}>
          {content}
        </span>
      )
    } else {
      const cls = CONTENT_CLASS[tk.kind]
      out.push(cls ? <span key={key++} className={cls}>{content}</span> : content)
    }
    pos = e
  }
  if (pos < text.length) out.push(text.slice(pos))
  return out
}

export function StaticCell({
  text,
  connections,
  onActivate
}: {
  text: string
  connections?: () => ConnectionsApi | undefined
  onActivate: (coords: { x: number; y: number }) => void
}): React.JSX.Element {
  return (
    <div
      className="mdpm-tbl-cell-static"
      onMouseDown={(e) => {
        if (e.button !== 0) return // left button edits; right falls through to the cell's context menu
        // Stop the browser's native mousedown focus/selection: the cell swaps to an editor that we focus
        // ourselves, and the native focus-shift otherwise races ours — the "needs two clicks" bug.
        e.preventDefault()
        onActivate({ x: e.clientX, y: e.clientY })
      }}
    >
      {renderCellContent(text, connections)}
    </div>
  )
}
