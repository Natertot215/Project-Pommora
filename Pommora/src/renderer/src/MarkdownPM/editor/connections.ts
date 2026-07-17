import { EditorView } from '@codemirror/view'
import { tokenize } from '../tokens'
import type { ConnectionsApi } from '../connections'

type GetApi = () => ConnectionsApi | undefined

function wikiLinkAt(view: EditorView, pos: number): { title: string } | null {
  const line = view.state.doc.lineAt(pos)
  const rel = pos - line.from
  const tk = tokenize(line.text).find(
    (t) => t.kind === 'wikiLink' && rel >= t.range[0] && rel <= t.range[1],
  )
  return tk ? { title: line.text.slice(tk.contentRange[0], tk.contentRange[1]) } : null
}

export function connectionClicks(getApi: GetApi): ReturnType<typeof EditorView.domEventHandlers> {
  return EditorView.domEventHandlers({
    // Navigate on a plain single-click (spec). Handled on `click`, not `mousedown`, and skipped when the
    // selection is non-empty — so dragging across a connection highlights it instead of navigating away.
    click(event, view) {
      if (event.button !== 0 || event.detail !== 1 || !view.state.selection.main.empty) return false
      const api = getApi()
      if (!api) return false
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
      if (pos == null) return false
      const hit = wikiLinkAt(view, pos)
      if (!hit) return false
      const res = api.resolve(hit.title)
      if (res.status !== 'resolved' || !res.page) return false
      event.preventDefault()
      api.open(res.page)
      return true
    },
    // Right-click on a resolved connection hands off to the host's menu hook (Open in Preview et al).
    contextmenu(event, view) {
      const api = getApi()
      if (!api?.menu) return false
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
      if (pos == null) return false
      const hit = wikiLinkAt(view, pos)
      if (!hit) return false
      const res = api.resolve(hit.title)
      if (res.status !== 'resolved' || !res.page) return false
      event.preventDefault()
      api.menu(res.page, { x: event.clientX, y: event.clientY })
      return true
    },
  })
}
